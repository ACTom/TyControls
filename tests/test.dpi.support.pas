unit test.dpi.support;
{ What a window handle would have done, for a runner that has none.

  A form in this console runner is never shown, so three things LCL does for a real one
  never happen: nothing aligns the controls, nothing re-fits the auto-sized ones, and a size
  floor that moved is not applied until somebody sets the bounds again. A test that wants to
  know where a form's controls END UP has to run those by hand, in the order LCL would.

  REGISTERS NO TESTS. The DPI suites that need a settled layout share this one. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Forms, Graphics, LCLType, LMessages;

{ The screen LCL creates fonts for. ScreenInfo is what TFont.Create reads and
  Screen.PixelsPerInch is a copy of it taken when the Screen object was made; both are set.
  The caller puts them back (TyTestScreenPPI reads the current value). }
procedure TyTestSimulateScreen(APPI: Integer);
function TyTestScreenPPI: Integer;

{ Align, auto-size and floor every control under AParent, top down. Call it twice when a
  container restyles its children while laying them out (a flat tool bar does). }
procedure TyTestSettle(AParent: TWinControl);

{ One line per control under ARoot, depth first: path|x|y|w|h|visible|fontPPI, the position
  relative to ARoot. }
procedure TyTestListTree(ARoot: TControl; AOut: TStrings);

{ Paint ARoot and everything visible under it into ATarget, which must be ARoot's size. What
  could not be painted is named in ALog and left out of the picture. }
procedure TyTestPaintTree(ARoot: TControl; ATarget: TBitmap; ALog: TStrings);

{ Pascal source with comments and string literals blanked out, so that prose ABOUT a
  construct cannot be taken for the construct. Brace comments NEST in this dialect, and the
  units under scan do use that. For the guards that read the library's own source. }
function TyTestCodeOnly(const S: string): string;
{ The repository root, with a trailing delimiter: the runner lives in tests/. }
function TyTestRepoRoot: string;

implementation

uses
  tyControls.Painter;

type
  { PaintWindow, AdjustClientRect and AlignControls are protected on TWinControl. }
  TWinControlAccess = class(TWinControl);

procedure TyTestSimulateScreen(APPI: Integer);
begin
  ScreenInfo.PixelsPerInchX := APPI;
  ScreenInfo.PixelsPerInchY := APPI;
  Screen.UpdateScreen;
  { The measurement memo is keyed on the CONTROL's PPI, not on the screen -- rightly, the
    screen is not supposed to be an input. Dropped here so that a comparison between two
    screens is never answered out of the first one's entries. }
  TyInvalidateTextMeasureCache;
end;

function TyTestScreenPPI: Integer;
begin
  Result := ScreenInfo.PixelsPerInchY;
end;

procedure TyTestSettle(AParent: TWinControl);
var
  r: TRect;
  i, pw, ph: Integer;
  c: TControl;
begin
  { The auto-size engine. LCL's DPI pass leaves an AutoSize control's re-fitted axes alone
    because the control is about to fit itself again; here nothing else would. }
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    if not c.AutoSize then Continue;
    pw := 0;
    ph := 0;
    c.InvalidatePreferredSize;
    c.GetPreferredSize(pw, ph, True, False);
    if pw <= 0 then pw := c.Width;
    if ph <= 0 then ph := c.Height;
    c.SetBounds(c.Left, c.Top, pw, ph);
  end;
  { The align engine. }
  r := AParent.ClientRect;
  TWinControlAccess(AParent).AdjustClientRect(r);
  TWinControlAccess(AParent).AlignControls(nil, r);
  { The size floors: a floor re-derived after a DPI pass can be a pixel above the box the
    pass produced, and LCL applies it the next time it sets the bounds. }
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    if (c.Width < c.Constraints.MinWidth) or (c.Height < c.Constraints.MinHeight) then
      c.SetBounds(c.Left, c.Top, Max(c.Width, c.Constraints.MinWidth),
        Max(c.Height, c.Constraints.MinHeight));
  end;
  for i := 0 to AParent.ControlCount - 1 do
    if AParent.Controls[i] is TWinControl then
      TyTestSettle(TWinControl(AParent.Controls[i]));
end;

procedure ListOne(AControl: TControl; const APath: string; AX, AY: Integer; AOut: TStrings);
var
  i: Integer;
  me: string;
begin
  me := APath + '/' + AControl.Name + ':' + AControl.ClassName;
  AOut.Add(Format('%s|%d|%d|%d|%d|%d|%d', [me, AX, AY, AControl.Width, AControl.Height,
    Ord(AControl.Visible), AControl.Font.PixelsPerInch]));
  if AControl is TWinControl then
    for i := 0 to TWinControl(AControl).ControlCount - 1 do
      ListOne(TWinControl(AControl).Controls[i], me,
        AX + TWinControl(AControl).Controls[i].Left,
        AY + TWinControl(AControl).Controls[i].Top, AOut);
end;

procedure TyTestListTree(ARoot: TControl; AOut: TStrings);
begin
  ListOne(ARoot, '', 0, 0, AOut);
end;

procedure PaintOne(AControl: TControl; ATarget: TBitmap; AX, AY: Integer; ALog: TStrings);
var
  bmp: TBitmap;
  w, h: Integer;
begin
  w := AControl.Width;
  h := AControl.Height;
  if (w <= 0) or (h <= 0) then Exit;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf24bit;
    bmp.SetSize(w, h);
    { Start from what is already there: a graphic control is drawn OVER its parent, and a
      windowed one fills itself from its parent's surface where it has none of its own. }
    bmp.Canvas.CopyRect(Rect(0, 0, w, h), ATarget.Canvas, Rect(AX, AY, AX + w, AY + h));
    try
      if AControl is TWinControl then
        TWinControlAccess(AControl).PaintWindow(bmp.Canvas.Handle)
      else
        AControl.Perform(LM_PAINT, WPARAM(bmp.Canvas.Handle), 0);
    except
      on E: Exception do
        if ALog <> nil then
          ALog.Add(Format('%s: %s could not be painted -- %s: %s',
            [AControl.Name, AControl.ClassName, E.ClassName, E.Message]));
    end;
    ATarget.Canvas.Draw(AX, AY, bmp);
  finally
    bmp.Free;
  end;
end;

procedure PaintBranch(AControl: TControl; ATarget: TBitmap; AX, AY: Integer;
  ALog: TStrings);
var
  i: Integer;
  wc: TWinControl;
  c: TControl;
begin
  PaintOne(AControl, ATarget, AX, AY, ALog);
  if not (AControl is TWinControl) then Exit;
  wc := TWinControl(AControl);
  { Graphic children first, then the windowed ones, which sit above them on a real form. }
  for i := 0 to wc.ControlCount - 1 do
  begin
    c := wc.Controls[i];
    if c.Visible and not (c is TWinControl) then
      PaintBranch(c, ATarget, AX + c.Left, AY + c.Top, ALog);
  end;
  for i := 0 to wc.ControlCount - 1 do
  begin
    c := wc.Controls[i];
    if c.Visible and (c is TWinControl) then
      PaintBranch(c, ATarget, AX + c.Left, AY + c.Top, ALog);
  end;
end;

procedure TyTestPaintTree(ARoot: TControl; ATarget: TBitmap; ALog: TStrings);
begin
  PaintBranch(ARoot, ATarget, 0, 0, ALog);
end;

function TyTestRepoRoot: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
end;

function TyTestCodeOnly(const S: string): string;
var
  i, n, depth: Integer;
  sb: TStringBuilder;
begin
  sb := TStringBuilder.Create;
  try
    i := 1;
    n := Length(S);
    while i <= n do
    begin
      if S[i] = '{' then
      begin
        depth := 1;
        Inc(i);
        while (i <= n) and (depth > 0) do
        begin
          if S[i] = '{' then Inc(depth)
          else if S[i] = '}' then Dec(depth);
          Inc(i);
        end;
        sb.Append(' ');
      end
      else if (S[i] = '(') and (i < n) and (S[i + 1] = '*') then
      begin
        Inc(i, 2);
        while (i < n) and not ((S[i] = '*') and (S[i + 1] = ')')) do Inc(i);
        Inc(i, 2);
        sb.Append(' ');
      end
      else if (S[i] = '/') and (i < n) and (S[i + 1] = '/') then
      begin
        while (i <= n) and (S[i] <> #10) do Inc(i);
        sb.Append(' ');
      end
      else if S[i] = '''' then
      begin
        Inc(i);
        while (i <= n) and (S[i] <> '''') do Inc(i);
        Inc(i);
        sb.Append(' ');
      end
      else
      begin
        sb.Append(S[i]);
        Inc(i);
      end;
    end;
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

end.
