{ Real-machine verification probe — TTyRadioGroup / TTyCheckGroup focus ring.

  Same road as gridverify / scrollverify: a real window, real handles, the real message
  path — assert, and save PNGs. It exists because the two defects it pins CANNOT be seen
  from the headless unit suite:

    1. "one click moves the dot but not the ring". The caret is OS state. On a form that
       was never shown CanFocus is False, SetFocus is skipped, and every assertion about
       Focused is vacuously true. tests/test.radiogroup.pas watches the group's focus
       REQUEST (TTyRadioGroup.FocusItem, virtual for exactly that); only this probe can
       watch the caret actually land.

    2. "the focus ring's bottom edge is cut off". The clipping is done by the NEXT ROW's
       child WINDOW, which is a later sibling and therefore higher in the z-order. Neither
       RenderTo nor GetFormImage knows anything about sibling z-order — both re-draw one
       control into an offscreen canvas — so both are blind to it by construction.
       PrintWindow drives WM_PRINT down the real HWND tree in real z-order, so what it
       returns is what the screen shows.

  Usage: radiofocusverify.exe [output-dir]     exit code 0 = every check passed.
  Windows-only (PrintWindow); on other widgetsets it reports SKIP and exits 0. }
program radiofocusverify;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  Interfaces, Forms, Graphics, Controls, Classes, SysUtils, Types, LCLType,
  tyControls.Base, tyControls.Controller, tyControls.CheckBox,
  tyControls.RadioGroup, tyControls.CheckGroup;

{$IFDEF LCLWin32}
function PrintWindow(hwnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL;
  stdcall; external 'user32.dll' name 'PrintWindow';
{$ENDIF}

type
  { protected-member hack, so the probe can ask the group what client area it laid out in }
  TCtrlHack = class(TTyCustomControl);

var
  OutDir: string;
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Say(const AMsg: string);
begin
  WriteLn(AMsg);
  Flush(Output);
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
    Say('  PASS  ' + AWhat)
  else
  begin
    Inc(Failures);
    if ADetail <> '' then
      Say('  FAIL  ' + AWhat + '   [' + ADetail + ']')
    else
      Say('  FAIL  ' + AWhat);
  end;
end;

{ ------------------------------------------------------------------------- }

type
  TProbeForm = class(TForm)
  public
    RG: TTyRadioGroup;
    CG: TTyCheckGroup;
    procedure Build;
    procedure Press(ACtl: TTyCustomControl);
    procedure Shoot(ACtl: TWinControl; const AName: string);
  end;

procedure TProbeForm.Build;
begin
  Caption := 'radiofocusverify';
  Position := poScreenCenter;
  Width := 360; Height := 240;
  Color := clWhite;

  { The containers example's exact box, so the numbers in this probe are the numbers in
    the screenshot the defect was reported from. }
  RG := TTyRadioGroup.Create(Self);
  RG.Parent := Self;
  RG.SetBounds(20, 20, 290, 94);
  RG.Caption := 'Size (2 columns)';
  RG.Columns := 2;
  RG.Items.Add('Extra small');
  RG.Items.Add('Small');
  RG.Items.Add('Medium');
  RG.Items.Add('Large');
  RG.ItemIndex := 1;

  CG := TTyCheckGroup.Create(Self);
  CG.Parent := Self;
  CG.SetBounds(20, 130, 290, 94);
  CG.Caption := 'Enable features (2 columns)';
  CG.Columns := 2;
  CG.Items.Add('Alpha');
  CG.Items.Add('Beta');
  CG.Items.Add('Gamma');
  CG.Items.Add('Delta');
end;

{ A left click delivered as the window messages Windows itself posts. Synthesised INPUT
  (mouse_event) is not usable here: a build machine has no interactive desktop and the event
  is swallowed by the input queue. Everything under test -- OnMouseDown, the group's
  FocusItem, TTyCustomControl.MouseDown's own focus gate, Click -> Checked -- runs in
  process off these two messages, which is the whole point. }
procedure TProbeForm.Press(ACtl: TTyCustomControl);
{$IFDEF LCLWin32}
var
  lp: LPARAM;
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  lp := ((ACtl.Height div 2) shl 16) or (ACtl.Width div 2);
  SendMessage(ACtl.Handle, WM_LBUTTONDOWN, MK_LBUTTON, lp);
  Application.ProcessMessages;
  SendMessage(ACtl.Handle, WM_LBUTTONUP, 0, lp);
  Application.ProcessMessages;
  {$ENDIF}
end;

procedure TProbeForm.Shoot(ACtl: TWinControl; const AName: string);
{$IFDEF LCLWin32}
var
  grp, bmp: TBitmap;
  png: TPortableNetworkGraphic;
  M: Integer;
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  if OutDir = '' then Exit;
  Application.ProcessMessages;
  M := 6;
  grp := TBitmap.Create;
  bmp := TBitmap.Create;
  png := TPortableNetworkGraphic.Create;
  try
    grp.PixelFormat := pf24bit;
    grp.SetSize(ACtl.Width, ACtl.Height);
    if not PrintWindow(ACtl.Handle, grp.Canvas.Handle, 0) then
      Say('  NOTE  PrintWindow failed for ' + AName);
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(ACtl.Width + 2 * M, ACtl.Height + 2 * M);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, bmp.Width, bmp.Height);
    bmp.Canvas.Draw(M, M, grp);
    png.Assign(bmp);
    png.SaveToFile(IncludeTrailingPathDelimiter(OutDir) + AName + '.png');
    Say('  shot  ' + AName + '.png');
  finally
    png.Free; bmp.Free; grp.Free;
  end;
  {$ENDIF}
end;

{ ------------------------------------------------------------------------- }

procedure RunChecks(F: TProbeForm);
var
  i, prevBottom, rowTop: Integer;
  client: TRect;
  b: TTyRadioButton;
  c: TTyCheckBox;
begin
  Say('--- 1. one click must move the ring WITH the dot -------------------');
  Say(Format('    start: checked=%d focused=%d', [F.RG.ItemIndex, F.RG.FocusedIndex]));

  F.Press(F.RG.Buttons[0]);
  Check('one press on item 0 checks it', F.RG.ItemIndex = 0,
    Format('ItemIndex=%d', [F.RG.ItemIndex]));
  Check('...and the SAME press moves the focus ring onto it',
    F.RG.FocusedIndex = 0,
    Format('FocusedIndex=%d -- the dot moved and the ring did not', [F.RG.FocusedIndex]));

  F.Press(F.RG.Buttons[3]);
  Check('a press on a far item moves both again',
    (F.RG.ItemIndex = 3) and (F.RG.FocusedIndex = 3),
    Format('checked=%d focused=%d', [F.RG.ItemIndex, F.RG.FocusedIndex]));

  Say('--- 2. arrow keys keep focus and check together --------------------');
  { Up from item 3 (row 1, col 1) lands on item 1 (row 0, col 1) in a 2-column row-major grid. }
  F.RG.Buttons[3].SetFocus;
  {$IFDEF LCLWin32}
  SendMessage(F.RG.Buttons[3].Handle, WM_KEYDOWN, VK_UP, 0);
  Application.ProcessMessages;
  {$ENDIF}
  Check('VK_UP moves the selection one row up', F.RG.ItemIndex = 1,
    Format('ItemIndex=%d', [F.RG.ItemIndex]));
  Check('...and the ring came with it', F.RG.FocusedIndex = 1,
    Format('FocusedIndex=%d', [F.RG.FocusedIndex]));

  { Space still toggles the option the caret is on -- untouched by this pass, but it is the
    third leg of the keyboard contract and the one a focus change is most likely to break. }
  F.RG.Buttons[2].SetFocus;
  {$IFDEF LCLWin32}
  SendMessage(F.RG.Buttons[2].Handle, WM_KEYDOWN, VK_SPACE, 0);
  Application.ProcessMessages;
  {$ENDIF}
  Check('Space selects the option the caret is on', F.RG.ItemIndex = 2,
    Format('ItemIndex=%d', [F.RG.ItemIndex]));

  Say('--- 3. exactly one tab stop, on the checked item -------------------');
  i := 0;
  for prevBottom := 0 to F.RG.Count - 1 do
    if F.RG.Buttons[prevBottom].TabStop then Inc(i);
  Check('one tab stop for the whole group', i = 1, Format('%d stops', [i]));
  Check('and it is on the checked item', F.RG.Buttons[F.RG.ItemIndex].TabStop);

  Say('--- 4. rows must not overlap (the ring is 2px at the row edge) -----');
  client := F.RG.ClientRect;
  TCtrlHack(F.RG).AdjustClientRect(client);
  { EDGE probe, deliberately: the overlap is at the BOUNDARY between two rows, and it is
    invisible on the last row because nothing sits below it to paint over it. }
  prevBottom := -1;
  for i := 0 to F.RG.Count - 1 do
  begin
    b := F.RG.Buttons[i];
    rowTop := b.Top;
    if (i >= 2) then      { 2 columns -> items 2,3 are the second row }
    begin
      prevBottom := F.RG.Buttons[i - 2].Top + F.RG.Buttons[i - 2].Height;
      Check(Format('radio row under item %d starts at or below the row above it', [i]),
        rowTop >= prevBottom,
        Format('item%d.Top=%d but item%d.Bottom=%d -- %d px of overlap eats the ring',
          [i, rowTop, i - 2, prevBottom, prevBottom - rowTop]));
    end;
    Check(Format('radio item %d stays inside the group client area', [i]),
      (b.Top >= client.Top) and (b.Top + b.Height <= client.Bottom),
      Format('item%d=(%d..%d) client=(%d..%d)',
        [i, b.Top, b.Top + b.Height, client.Top, client.Bottom]));
  end;

  Say('--- 5. the check-group sibling tiles the same way ------------------');
  client := F.CG.ClientRect;
  TCtrlHack(F.CG).AdjustClientRect(client);
  for i := 0 to F.CG.Count - 1 do
  begin
    c := F.CG.Buttons[i];
    if i >= 2 then
    begin
      prevBottom := F.CG.Buttons[i - 2].Top + F.CG.Buttons[i - 2].Height;
      Check(Format('check row under item %d starts at or below the row above it', [i]),
        c.Top >= prevBottom,
        Format('item%d.Top=%d but item%d.Bottom=%d', [i, c.Top, i - 2, prevBottom]));
    end;
    Check(Format('check item %d stays inside the group client area', [i]),
      (c.Top >= client.Top) and (c.Top + c.Height <= client.Bottom),
      Format('item%d=(%d..%d) client=(%d..%d)',
        [i, c.Top, c.Top + c.Height, client.Top, client.Bottom]));
  end;
  F.Press(F.CG.Buttons[2]);
  Check('one press on a checkbox checks AND focuses it',
    F.CG.Buttons[2].Checked and F.CG.Buttons[2].Focused);

  Say('--- 6. screenshots -------------------------------------------------');
  { The user's literal gesture: click "Extra small" (twice -- before the fix the FIRST click
    did not move the ring, which is half the report), then ONE click on "Small".
    Before the fix that leaves the ring on item 0 and the dot on item 1, with the ring's
    bottom edge hidden under the overlapping next row. After it, both are on item 1 and the
    ring is a closed pill. }
  F.Press(F.RG.Buttons[0]);
  F.Press(F.RG.Buttons[0]);
  F.Press(F.RG.Buttons[1]);
  Say(Format('    shot state: checked=%d focused=%d', [F.RG.ItemIndex, F.RG.FocusedIndex]));
  F.Shoot(F.RG, 'radiogroup-focus');
  F.Shoot(F.CG, 'checkgroup-rows');
end;

var
  F: TProbeForm;
begin
  if ParamCount >= 1 then OutDir := ParamStr(1) else OutDir := '';
  Application.Initialize;
  F := TProbeForm.CreateNew(Application);
  F.Build;
  F.Show;
  Application.ProcessMessages;
  {$IFDEF LCLWin32}
  SetForegroundWindow(F.Handle);
  SetActiveWindow(F.Handle);
  {$ENDIF}
  Application.ProcessMessages;
  {$IFNDEF LCLWin32}
  Say('SKIP: radiofocusverify needs the Win32 widgetset (PrintWindow + WM_ messages).');
  Halt(0);
  {$ENDIF}
  try
    RunChecks(F);
  except
    on E: Exception do
    begin
      Inc(Failures);
      Say('  FAIL  exception: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
  Say('');
  Say(Format('%d checks, %d failures', [Checks, Failures]));
  if Failures = 0 then Halt(0) else Halt(1);
end.
