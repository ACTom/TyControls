{ coolbarrejoin —— the real-machine probe for the TTyCoolBar "a band can never be dragged
  back UP to row 0" report (examples/containers).

  WHY A PROBE AND NOT A UNIT TEST. The unit suite builds its band rects BY HAND
  (test.coolbar.pas MakeBand sets each child's BoundsRect directly) because the LCL align
  engine does not run for a form that was never shown -- AutoSizeDelayedHandle short-circuits
  the whole tree. So a headless test can pin the MODEL (widths, Break flags, child order) but
  it structurally cannot answer the user's actual question, which is "after the gesture, is the
  band on row 0 on screen?". That answer needs a shown window and a real AlignControls pass.

  INPUT MODE -- READ THIS BEFORE BELIEVING ANY RESULT. `qwinsta` on this machine reports our
  session as Disc(onnected): there is no interactive input queue, so mouse_event / SendInput
  are delivered nowhere and every gesture built on them reads as "nothing happened" -- an
  environment red masquerading as a control red. This probe therefore drives the control with
  WM_LBUTTONDOWN / WM_MOUSEMOVE / WM_LBUTTONUP SendMessage'd straight at the control's HWND,
  which goes through the real WndProc -> LCL -> TTyCoolBar.MouseDown/Move/Up path. The only
  difference from a real hand is who posts the message.

  And because "the messages arrive at all" is itself an assumption, Case_0 is a POSITIVE
  CONTROL: it performs a gesture that is known to work (the gripper seam resize that landed in
  3ac97c6) with the exact same posting helpers. If Case_0 passes and Case_2 fails, the inert
  gesture is the control's, not the harness's.

  Usage:  coolbarrejoin.exe [outdir]      exit code 0 = every check passed.
          Pass --before to run against the UNFIXED control: the rejoin checks are then
          EXPECTED to fail and the exit code is inverted, so the recorded "before" run is a
          green run that proves the defect reproduces.

  THE DEFECT HAD TWO HALVES and the revert you choose decides which one you see, so both are
  worth reproducing:

    * revert only TTyCoolBar.MouseMove's `RejoinRow(X, Y, wantRow)` back to
      `SetBandBreak(FDragCtl, False)` -> case 2 shows the band simply not moving. That is the
      inert gesture: the band came down by overflow, so its Break was already False and
      clearing it changes nothing.
    * ALSO put `ReorderFromPointer` back in front of the row decision -> case 2 shows the two
      bands SWAPPING instead. An intermediate pointer position crosses band 0's midpoint on the
      way up, the reorder answers first and consumes the drag. That is why the user reported
      the swap as the only gesture that still responded. }
program coolbarrejoin;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types,
  StrUtils, Math, LCLType, LCLIntf,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.Panel, tyControls.ControlBar, tyControls.CoolBar,
  tyControls.Button, tyControls.ToolBar, tyControls.ToolBarEx, tyControls.Edit;

type
  { The protected geometry the probe needs, exposed the same way test.coolbar.pas does. }
  TBarAccess = class(TTyCoolBar)
  public
    function ContentBox: TRect;
    function GripPx: Integer;
    function BandRect(ACtl: TControl): TRect;
  end;

var
  OutDir: string;
  Failures: Integer = 0;
  Checks: Integer = 0;
  LogF: TextFile;
  LogOpen: Boolean = False;
  BeforeMode: Boolean = False;
  Form: TForm;
  Bar: TBarAccess;
  B0, B1, B2: TTyPanel;

function TBarAccess.ContentBox: TRect;             begin Result := BandContentRect; end;
function TBarAccess.GripPx: Integer;               begin Result := GripperWidthPx; end;
function TBarAccess.BandRect(ACtl: TControl): TRect; begin Result := BandRectFor(ACtl); end;

procedure Say(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
  if LogOpen then
  begin
    WriteLn(LogF, AMsg);
    Flush(LogF);
  end;
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
    Say('  PASS  ' + AWhat)
  else
  begin
    Inc(Failures);
    Say('  FAIL  ' + AWhat + IfThen(ADetail <> '', '  <- ' + ADetail, ''));
  end;
end;

procedure Note(const AWhat: string);
begin
  Say('  ....  ' + AWhat);
end;

procedure Pump(ATimes: Integer = 4);
var i: Integer;
begin
  for i := 1 to ATimes do
  begin
    Application.ProcessMessages;
    Sleep(4);
  end;
end;

function R2S(const R: TRect): string;
begin
  Result := Format('(%d,%d)-(%d,%d)', [R.Left, R.Top, R.Right, R.Bottom]);
end;

{$IFDEF LCLWin32}
{ The three helpers every gesture below is built from. SendMessage, not mouse_event: see the
  unit header -- our session is disconnected, so the OS input queue delivers nothing. }
procedure MouseDownAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_LBUTTONDOWN, MK_LBUTTON,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;

procedure MouseMoveAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_MOUSEMOVE, MK_LBUTTON,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;

procedure MouseUpAt(AControl: TWinControl; AX, AY: Integer);
begin
  Windows.SendMessage(AControl.Handle, WM_LBUTTONUP, 0,
    LPARAM((AY shl 16) or (AX and $FFFF)));
  Pump(2);
end;

{ A drag in STEPS, the way a hand produces it: one down, several moves, one up. A single jump
  move would hide any rule that only fires while the pointer is travelling. }
procedure DragBy(AControl: TWinControl; AX, AY, ADx, ADy, ASteps: Integer);
var i: Integer;
begin
  MouseDownAt(AControl, AX, AY);
  for i := 1 to ASteps do
    MouseMoveAt(AControl, AX + MulDiv(ADx, i, ASteps), AY + MulDiv(ADy, i, ASteps));
  MouseUpAt(AControl, AX + ADx, AY + ADy);
  Pump(6);
end;
{$ELSE}
procedure DragBy(AControl: TWinControl; AX, AY, ADx, ADy, ASteps: Integer);
begin
  Say('  SKIP  real-input drag needs LCLWin32');
end;
{$ENDIF}

{ ------------------------------------------------------------------ the scene -- }
procedure BuildScene;
begin
  Form := TForm.CreateNew(nil);
  Form.Name := 'ProbeForm';
  Form.Caption := 'coolbarrejoin probe';
  Form.SetBounds(60, 60, 520, 300);

  Bar := TBarAccess.Create(Form);
  Bar.Parent := Form;
  Bar.Align := alTop;
  Bar.Height := 90;
  Bar.GripperWidth := 10;

  B0 := TTyPanel.Create(Bar); B0.Parent := Bar; B0.SetBounds(0, 0, 90, 26); B0.Name := 'B0';
  B1 := TTyPanel.Create(Bar); B1.Parent := Bar; B1.SetBounds(0, 0, 90, 26); B1.Name := 'B1';
  B2 := nil;

  Form.Show;
  Pump(10);
end;

procedure ResetScene;
begin
  Bar.SetBandWidth(B0, 90);
  Bar.SetBandWidth(B1, 90);
  Bar.SetBandBreak(B0, False);
  Bar.SetBandBreak(B1, False);
  if Bar.GetControlIndex(B0) <> 0 then Bar.SetControlIndex(B0, 0);
  Bar.Relayout;
  Pump(6);
end;

{ ============================================================== the cases ==== }

{ CASE 0 -- POSITIVE CONTROL. Does a posted-message gesture reach the control at all?
  The gripper seam resize (3ac97c6) is the known-good gesture: grabbing B1's gripper and
  dragging RIGHT must widen B0, the band the seam belongs to. If this is inert, every other
  result in this file is meaningless and the harness is what is broken. }
procedure Case_0_PostedMessagesReachTheControl;
var
  before: Integer;
  g: TRect;
begin
  Say('[0] positive control: posted messages drive the known-good gripper resize');
  ResetScene;
  before := B0.Width;
  g := Bar.BandRect(B1);
  Note(Format('B0=%s B1=%s  B1 grip=%s', [R2S(B0.BoundsRect), R2S(B1.BoundsRect), R2S(g)]));
  Check('precondition: B1 has a gripper strip to grab', g.Right > g.Left, R2S(g));
  Check('precondition: both bands start on row 0', B0.Top = B1.Top,
    Format('B0.Top=%d B1.Top=%d', [B0.Top, B1.Top]));

  DragBy(Bar, (g.Left + g.Right) div 2, (g.Top + g.Bottom) div 2, 60, 0, 6);

  Check('a posted-message drag really moves the seam (B0 grew)', B0.Width > before,
    Format('B0.Width %d -> %d', [before, B0.Width]));
end;

{ CASE 1 -- reproduce the user's setup. Widen band 0 until band 1 can no longer share the row;
  band 1 must land on row 1. This half is CORRECT behaviour and must hold before and after. }
procedure Case_1_OverflowPushesTheSecondBandDown;
var
  g: TRect;
begin
  Say('[1] widening band 0 pushes band 1 onto row 1 (overflow, NOT Break)');
  ResetScene;
  g := Bar.BandRect(B1);
  DragBy(Bar, (g.Left + g.Right) div 2, (g.Top + g.Bottom) div 2, 340, 0, 10);

  Note(Format('B0=%s B1=%s content=%s', [R2S(B0.BoundsRect), R2S(B1.BoundsRect),
    R2S(Bar.ContentBox)]));
  Check('band 1 was pushed onto the next row', B1.Top > B0.Top,
    Format('B0.Top=%d B1.Top=%d', [B0.Top, B1.Top]));
  Check('and it got there by OVERFLOW -- its Break is still False, which is exactly why '
      + 'clearing Break cannot bring it back', not Bar.BandBreak(B1),
    'BandBreak(B1)=' + BoolToStr(Bar.BandBreak(B1), True));
end;

{ CASE 2 -- THE DEFECT. Drag band 1's gripper UP onto row 0, aiming at the RIGHT half of
  band 0 so the midpoint rule does not turn the gesture into a swap. Before the fix this is
  silently inert; after it, band 0 gives up width and band 1 rejoins row 0. }
procedure Case_2_DragBackUpRejoinsRow0;
var
  g: TRect;
  wasW, dy: Integer;
begin
  Say('[2] dragging band 1 back UP onto the full row 0');
  // (scene is whatever case 1 left: B0 wide, B1 on row 1)
  Check('precondition: band 1 really is on row 1', B1.Top > B0.Top,
    Format('B0.Top=%d B1.Top=%d', [B0.Top, B1.Top]));
  wasW := B0.Width;
  g := Bar.BandRect(B1);
  dy := B0.Top - B1.Top;                    // straight up, one row
  Note(Format('grabbing B1 grip %s and dragging dy=%d, landing on B0''s RIGHT half',
    [R2S(g), dy]));

  { X lands past B0's midpoint on purpose: that is the half where TyCoolBandDropIndex answers
    "stay put", so the reorder cannot be what produces the result. }
  DragBy(Bar, (g.Left + g.Right) div 2, (g.Top + g.Bottom) div 2,
    (B0.Left + MulDiv(B0.Width, 4, 5)) - ((g.Left + g.Right) div 2), dy, 8);

  Note(Format('after: B0=%s B1=%s', [R2S(B0.BoundsRect), R2S(B1.BoundsRect)]));
  Check('band 1 is back on row 0', B1.Top = B0.Top,
    Format('B0.Top=%d B1.Top=%d', [B0.Top, B1.Top]));
  Check('band 0 gave up the width that made room', B0.Width < wasW,
    Format('B0.Width %d -> %d', [wasW, B0.Width]));
  Check('band 0 was not shrunk below its floor', B0.Width >= Bar.BandMinWidth(B0),
    Format('B0.Width=%d min=%d', [B0.Width, Bar.BandMinWidth(B0)]));
end;

{ CASE 3 -- the refusal. Nail band 0 to its own width with MinWidth = its current width; there
  is then no slack anywhere on row 0, so the rejoin CANNOT succeed. The pinned contract is
  "refuse and leave the band where it is" -- the band stays on row 1 and NOTHING else moves. }
procedure Case_3_RefusalLeavesEverythingAlone;
var
  g: TRect;
  w0, top1, dy: Integer;
begin
  Say('[3] a rejoin that cannot fit even at every minimum is refused, not half-applied');
  ResetScene;
  g := Bar.BandRect(B1);
  DragBy(Bar, (g.Left + g.Right) div 2, (g.Top + g.Bottom) div 2, 340, 0, 10);
  Check('precondition: band 1 is on row 1 again', B1.Top > B0.Top,
    Format('B0.Top=%d B1.Top=%d', [B0.Top, B1.Top]));

  Bar.SetBandMinWidth(B0, B0.Width);       // no slack at all
  Pump(4);
  w0 := B0.Width;
  top1 := B1.Top;
  g := Bar.BandRect(B1);
  dy := B0.Top - B1.Top;
  DragBy(Bar, (g.Left + g.Right) div 2, (g.Top + g.Bottom) div 2,
    (B0.Left + MulDiv(B0.Width, 4, 5)) - ((g.Left + g.Right) div 2), dy, 8);

  Check('band 1 stayed where it was', B1.Top = top1,
    Format('B1.Top %d -> %d', [top1, B1.Top]));
  Check('and band 0 was not shrunk a pixel below its floor', B0.Width = w0,
    Format('B0.Width %d -> %d', [w0, B0.Width]));
  Bar.SetBandMinWidth(B0, 0);
end;

{ CASE 4 -- what the hosted controls can actually TELL us about their content width. The
  content cap has to be derived from something the control itself declares; this case prints
  every candidate for the two band contents the containers example really uses (a toolbar with
  three buttons, and an edit), so the choice of source is measured rather than assumed. }
procedure Case_4_WhatAControlDeclaresAboutItsWidth;
var
  Host: TForm;
  TB: TTyToolBarEx;
  Ed: TTyEdit;
  i, rw, rh, aw, ah: Integer;
  b: TTyToolButton;

  procedure Report(const AName: string; C: TControl);
  begin
    rw := 0; rh := 0; aw := 0; ah := 0;
    C.GetPreferredSize(rw, rh, True, False);     // Raw: 0 == "no opinion"
    C.GetPreferredSize(aw, ah, False, True);     // adjusted: falls back to Width
    Note(Format('%-12s Width=%-5d rawPref=%-5d adjPref=%-5d Constraints.MaxWidth=%d',
      [AName, C.Width, rw, aw, C.Constraints.MaxWidth]));
  end;

begin
  Say('[4] what a hosted control declares about how wide it can usefully be');
  Host := TForm.CreateNew(nil);
  try
    Host.SetBounds(0, 0, 600, 200);
    TB := TTyToolBarEx.Create(Host);
    TB.Parent := Host;
    TB.Wrapable := False;
    TB.SetBounds(0, 0, 170, 30);
    for i := 1 to 3 do
    begin
      b := TTyToolButton.Create(TB);
      b.Parent := TB;
      b.Caption := 'Btn' + IntToStr(i);
    end;
    Ed := TTyEdit.Create(Host);
    Ed.Parent := Host;
    Ed.SetBounds(0, 40, 140, 30);
    Host.Show;
    Pump(8);
    Report('toolbarEx', TB);
    Report('edit', Ed);
    Report('panel', B0);
    Host.Hide;
  finally
    Host.Free;
  end;
end;

{ ================================================================= main ===== }
var
  i: Integer;
  rejoinFailures: Integer;
begin
  OutDir := ExtractFilePath(ParamStr(0));
  for i := 1 to ParamCount do
    if ParamStr(i) = '--before' then BeforeMode := True
    else OutDir := ParamStr(i);
  ForceDirectories(OutDir);

  Application.Initialize;
  BuildScene;

  AssignFile(LogF, IncludeTrailingPathDelimiter(OutDir) + 'coolbarrejoin.log');
  Rewrite(LogF);
  LogOpen := True;
  Say('=== coolbarrejoin: TTyCoolBar drag-a-band-back-up probe ===');
  Say('mode: ' + IfThen(BeforeMode, 'BEFORE (the rejoin checks are expected to FAIL)', 'AFTER'));
  Say('input: WM_LBUTTONDOWN/WM_MOUSEMOVE/WM_LBUTTONUP via SendMessage -- the session is '
    + 'disconnected, so mouse_event would deliver nothing');
  Say('');

  try
    Case_0_PostedMessagesReachTheControl; Say('');
    Case_1_OverflowPushesTheSecondBandDown; Say('');
    rejoinFailures := Failures;
    Case_2_DragBackUpRejoinsRow0; Say('');
    Case_3_RefusalLeavesEverythingAlone; Say('');
    rejoinFailures := Failures - rejoinFailures;
    Case_4_WhatAControlDeclaresAboutItsWidth; Say('');
  except
    on E: Exception do
    begin
      Inc(Failures);
      rejoinFailures := 1;
      Say('  EXCEPTION  ' + E.ClassName + ': ' + E.Message);
    end;
  end;

  Say(Format('=== %d checks, %d failures ===', [Checks, Failures]));
  if LogOpen then CloseFile(LogF);
  Form.Hide;

  if BeforeMode then
  begin
    { A "before" run is green when the defect REPRODUCES: cases 0 and 1 must pass (the harness
      works and the setup is right) and case 2/3 must fail. }
    if (Failures - rejoinFailures > 0) or (rejoinFailures = 0) then Halt(1);
    Halt(0);
  end;
  if Failures > 0 then Halt(1);
end.
