unit tyGalleryCapture;

{$mode objfpc}{$H+}

{ Screenshots of one example, for docs/gallery.

  Linked ONLY into the copies scripts/make-gallery.ps1 builds under .gallery-build/ -- never
  into an example or the library. It does nothing unless TY_GALLERY_DIR names a folder; then,
  once the main form is showing, it shoots

    * every page of every top-level TTyPageControl (a page control inside another one keeps
      its default page), or the form as it opens when it has none -- first in light, then in
      dark, switched through the example's OWN "Dark" switch (or its Light/Dark buttons), so
      the switch in the picture says what the picture shows;
    * when TY_GALLERY_SKINS lists theme names, each of them picked in the example's
      ThemeCombo (the demo's skin wall);

  writes <view>-light.png / <view>-dark.png / skin-<name>.png and capture.log into that
  folder, and ends the application. The window is kept on top while it runs and copied off
  the screen inside the frame DWM draws, so a picture is what the screen shows (PrintWindow,
  even with PW_RENDERFULLCONTENT, returns nothing for these windows). Windows only.

  It runs as a list of steps, one per tick of a timer whose interval is the wait before the
  next step -- never a loop that pumps messages itself. An example that animates keeps its
  message queue from ever running dry: Application's idle handlers and async queue then never
  run, and a ProcessMessages loop never returns. A timer tick still arrives, and between two
  ticks the application paints the way it always does. }

interface

implementation

uses
  Classes, SysUtils, Types, Windows, Forms, Controls, Graphics, ExtCtrls, FPImage, FPWritePNG,
  ZStream, BGRABitmap, BGRABitmapTypes,
  tyControls.PageControl, tyControls.TabSheet, tyControls.ToggleSwitch, tyControls.Button,
  tyControls.ComboBox;

type
  TButtonAccess = class(TTyButton);

  TStepKind = (skPrepare, skMode, skPage, skShot, skRestore, skSkin, skDone);

  TStep = class
    Kind: TStepKind;
    Page: TTyPageControl;   // skPage, skRestore
    Index: Integer;         // skPage, skRestore: page index; skSkin: skin index
    Name: string;           // skShot: file name; skMode: 'light' / 'dark'
    Wait: Integer;          // ms before the NEXT step
  end;

  TGallery = class
  private
    FDir: string;
    FSkins: TStringList;
    FLog: TStringList;
    FTimer: TTimer;
    FSteps: TList;
    FNext: Integer;
    procedure FormAdded(Sender: TObject; AForm: TCustomForm);
    procedure Tick(Sender: TObject);
    procedure Plan(AForm: TCustomForm);
    procedure Add(AKind: TStepKind; AWait: Integer; const AName: string = '';
      APage: TTyPageControl = nil; AIndex: Integer = -1);
    procedure DoStep(AForm: TCustomForm; AStep: TStep);
    procedure Finish;
    procedure Log(const S: string);
    procedure Shoot(AForm: TCustomForm; const AName: string);
    function SetDark(AForm: TCustomForm; ADark: Boolean): Boolean;
    procedure MoveFromUnderCursor(AForm: TCustomForm);
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
  end;

var
  Gallery: TGallery = nil;

const
  DWMWA_EXTENDED_FRAME_BOUNDS = 9;
  CAPTUREBLT = $40000000;

{ The rectangle DWM draws for the window (without the invisible resize margins); False where
  there is no DWM. Looked up at run time: dwmapi.dll is not on XP. }
function DwmFrameBounds(AWnd: HWND; out R: TRect): Boolean;
type
  TGetAttr = function(hwnd: HWND; attr: DWORD; pv: Pointer; cb: DWORD): HRESULT; stdcall;
var
  lib: HMODULE;
  fn: TGetAttr;
begin
  Result := False;
  lib := LoadLibrary('dwmapi.dll');
  if lib = 0 then Exit;
  try
    fn := TGetAttr(GetProcAddress(lib, 'DwmGetWindowAttribute'));
    if Assigned(fn) then
      Result := fn(AWnd, DWMWA_EXTENDED_FRAME_BOUNDS, @R, SizeOf(R)) = S_OK;
  finally
    FreeLibrary(lib);
  end;
end;

{ A file-name part: letters, digits and dashes, lower case. }
function Slug(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z'] then c := Chr(Ord(c) + 32);
    if c in ['a'..'z', '0'..'9'] then
      Result := Result + c
    else if (Result <> '') and (Result[Length(Result)] <> '-') then
      Result := Result + '-';
  end;
  while (Result <> '') and (Result[Length(Result)] = '-') do
    SetLength(Result, Length(Result) - 1);
  if Result = '' then Result := 'page';
end;

{ Every visible TTyPageControl under AParent that is not inside another one. }
procedure CollectPageControls(AParent: TWinControl; AList: TList);
var
  i: Integer;
  c: TControl;
begin
  for i := 0 to AParent.ControlCount - 1 do
  begin
    c := AParent.Controls[i];
    if not c.Visible then Continue;
    if c is TTyPageControl then
      AList.Add(c)
    else if c is TWinControl then
      CollectPageControls(TWinControl(c), AList);
  end;
end;

{ The first component of AForm whose caption is ACaption and that is a toggle switch (or,
  with AButton, a button). }
function FindByCaption(AForm: TCustomForm; const ACaption: string; AButton: Boolean): TComponent;
var
  i: Integer;
  c: TComponent;
begin
  Result := nil;
  for i := 0 to AForm.ComponentCount - 1 do
  begin
    c := AForm.Components[i];
    if (not AButton) and (c is TTyToggleSwitch) and (TTyToggleSwitch(c).Caption = ACaption) then
      Exit(c);
    if AButton and (c is TTyButton) and (TTyButton(c).Caption = ACaption) then
      Exit(c);
  end;
end;

constructor TGallery.Create(const ADir: string);
var
  s: string;
begin
  inherited Create;
  FDir := IncludeTrailingPathDelimiter(ADir);
  FLog := TStringList.Create;
  FSteps := TList.Create;
  FSkins := TStringList.Create;
  FSkins.StrictDelimiter := True;
  FSkins.Delimiter := ',';
  s := SysUtils.GetEnvironmentVariable('TY_GALLERY_SKINS');
  if s <> '' then FSkins.DelimitedText := s;
  Screen.AddHandlerFormAdded(@FormAdded);
end;

destructor TGallery.Destroy;
var
  i: Integer;
begin
  FTimer.Free;
  for i := 0 to FSteps.Count - 1 do
    TObject(FSteps[i]).Free;
  FSteps.Free;
  FSkins.Free;
  FLog.Free;
  inherited Destroy;
end;

{ The timer is made once the first form exists: on Win32 a timer hangs off the application
  window, which Application.Initialize makes -- a timer made during unit initialisation
  never fires. }
procedure TGallery.FormAdded(Sender: TObject; AForm: TCustomForm);
begin
  if FTimer <> nil then Exit;
  Screen.RemoveHandlerFormAdded(@FormAdded);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 300;
  FTimer.OnTimer := @Tick;
  FTimer.Enabled := True;
end;

procedure TGallery.Log(const S: string);
begin
  FLog.Add(S);
  try
    ForceDirectories(FDir);
    FLog.SaveToFile(FDir + 'capture.log');
  except
    // a log that cannot be written must not stop the pictures
  end;
end;

procedure TGallery.Add(AKind: TStepKind; AWait: Integer; const AName: string;
  APage: TTyPageControl; AIndex: Integer);
var
  st: TStep;
begin
  st := TStep.Create;
  st.Kind := AKind;
  st.Wait := AWait;
  st.Name := AName;
  st.Page := APage;
  st.Index := AIndex;
  FSteps.Add(st);
end;

{ Everything to do, decided once the form is showing. }
procedure TGallery.Plan(AForm: TCustomForm);
const
  Modes: array[0..1] of string = ('light', 'dark');
var
  pcs: TList;
  i, j, k: Integer;
  pc: TTyPageControl;
  base: string;
begin
  pcs := TList.Create;
  try
    CollectPageControls(AForm, pcs);
    Log(Format('form %s %dx%d, %d top-level page control(s)', [AForm.Name, AForm.Width,
      AForm.Height, pcs.Count]));
    Add(skPrepare, 1500);
    for k := 0 to 1 do
    begin
      Add(skMode, 900, Modes[k]);
      if pcs.Count = 0 then
        Add(skShot, 50, 'main-' + Modes[k])
      else
        for i := 0 to pcs.Count - 1 do
        begin
          pc := TTyPageControl(pcs[i]);
          for j := 0 to pc.PageCount - 1 do
          begin
            if not pc.Pages[j].TabVisible then Continue;
            Add(skPage, 500, '', pc, j);
            base := Format('%.2d-%s', [j + 1, Slug(pc.Pages[j].Caption)]);
            if pcs.Count > 1 then base := Slug(pc.Name) + '-' + base;
            Add(skShot, 50, base + '-' + Modes[k]);
          end;
          Add(skRestore, 50, '', pc, pc.ActivePageIndex);
        end;
    end;
    if FSkins.Count > 0 then
    begin
      Add(skMode, 700, 'light');
      for i := 0 to FSkins.Count - 1 do
      begin
        Add(skSkin, 1300, '', nil, i);
        Add(skShot, 50, 'skin-' + Slug(FSkins[i]));
      end;
    end;
    Add(skDone, 0);
  finally
    pcs.Free;
  end;
end;

procedure TGallery.Tick(Sender: TObject);
var
  f: TCustomForm;
  st: TStep;
begin
  FTimer.Enabled := False;
  f := Application.MainForm;
  try
    if FSteps.Count = 0 then
    begin
      if (f = nil) or not f.Visible or not f.HandleAllocated then
      begin
        FTimer.Enabled := True;   // not showing yet: look again next tick
        Exit;
      end;
      Plan(f);
    end;
    if FNext >= FSteps.Count then Exit;
    st := TStep(FSteps[FNext]);
    Inc(FNext);
    DoStep(f, st);
    if st.Kind = skDone then Exit;
    if st.Wait > 0 then FTimer.Interval := st.Wait else FTimer.Interval := 10;
    FTimer.Enabled := True;
  except
    on E: Exception do
    begin
      Log('FAILED: ' + E.ClassName + ': ' + E.Message);
      Finish;
    end;
  end;
end;

procedure TGallery.DoStep(AForm: TCustomForm; AStep: TStep);
var
  combo: TComponent;
  j: Integer;
begin
  case AStep.Kind of
    skPrepare:
      begin
        MoveFromUnderCursor(AForm);
        SetWindowPos(AForm.Handle, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE);
        SetForegroundWindow(AForm.Handle);
      end;
    skMode:
      if not SetDark(AForm, AStep.Name = 'dark') then
        Log('no Dark switch and no Light/Dark buttons: ' + AStep.Name +
          ' is the form as it opens');
    skPage, skRestore:
      if AStep.Index >= 0 then AStep.Page.ActivePageIndex := AStep.Index;
    skShot:
      Shoot(AForm, AStep.Name);
    skSkin:
      begin
        combo := AForm.FindComponent('ThemeCombo');
        if not (combo is TTyComboBox) then
          Log('skins asked for, but the form has no ThemeCombo')
        else
        begin
          j := TTyComboBox(combo).Items.IndexOf(FSkins[AStep.Index]);
          if j < 0 then
            Log('skin not in ThemeCombo: ' + FSkins[AStep.Index])
          else
            TTyComboBox(combo).ItemIndex := j;
        end;
      end;
    skDone:
      begin
        Log('done');
        Finish;
      end;
  end;
end;

procedure TGallery.Finish;
begin
  FTimer.Enabled := False;
  Application.Terminate;
end;

{ A window under the pointer shows whatever is hovered: move it to the other side. }
procedure TGallery.MoveFromUnderCursor(AForm: TCustomForm);
var
  p: TPoint;
  wa: TRect;
begin
  wa := Screen.WorkAreaRect;
  { on the screen as a whole: a picture is copied off it }
  if AForm.Left + AForm.Width > wa.Right then AForm.Left := wa.Right - AForm.Width;
  if AForm.Top + AForm.Height > wa.Bottom then AForm.Top := wa.Bottom - AForm.Height;
  if AForm.Left < wa.Left then AForm.Left := wa.Left;
  if AForm.Top < wa.Top then AForm.Top := wa.Top;
  if not GetCursorPos(p) then Exit;
  if not PtInRect(AForm.BoundsRect, p) then Exit;
  if p.X < (wa.Left + wa.Right) div 2 then
    AForm.Left := wa.Right - AForm.Width
  else
    AForm.Left := wa.Left;
  if PtInRect(AForm.BoundsRect, p) then
  begin
    if p.Y < (wa.Top + wa.Bottom) div 2 then
      AForm.Top := wa.Bottom - AForm.Height
    else
      AForm.Top := wa.Top;
  end;
end;

function TGallery.SetDark(AForm: TCustomForm; ADark: Boolean): Boolean;
var
  c: TComponent;
begin
  Result := True;
  c := FindByCaption(AForm, 'Dark', False);
  if c <> nil then
  begin
    TTyToggleSwitch(c).Checked := ADark;
    Exit;
  end;
  if ADark then
    c := FindByCaption(AForm, 'Dark', True)
  else
    c := FindByCaption(AForm, 'Light', True);
  if c <> nil then
  begin
    TButtonAccess(c).Click;
    Exit;
  end;
  Result := False;
end;

procedure TGallery.Shoot(AForm: TCustomForm; const AName: string);
var
  h: HWND;
  fr: TRect;
  b: TBitmap;
  sdc: HDC;
  shot: TBGRABitmap;
  w: TFPWriterPNG;
begin
  h := AForm.Handle;
  { Whatever is still invalid is painted now, before the picture. }
  RedrawWindow(h, nil, 0, RDW_INVALIDATE or RDW_UPDATENOW or RDW_ALLCHILDREN);
  if not DwmFrameBounds(h, fr) then GetWindowRect(h, fr);
  b := TBitmap.Create;
  try
    b.PixelFormat := pf24bit;
    b.SetSize(fr.Right - fr.Left, fr.Bottom - fr.Top);
    b.Canvas.Changing;
    sdc := GetDC(0);
    try
      if not BitBlt(b.Canvas.Handle, 0, 0, b.Width, b.Height, sdc, fr.Left, fr.Top,
        SRCCOPY or CAPTUREBLT) then
        Log('BitBlt failed for ' + AName);
    finally
      ReleaseDC(0, sdc);
    end;
    b.Canvas.Changed;
    shot := TBGRABitmap.Create(b);
  finally
    b.Free;
  end;
  try
    w := TFPWriterPNG.Create;
    try
      w.UseAlpha := False;
      w.CompressionLevel := clmax;
      ForceDirectories(FDir);
      shot.SaveToFile(FDir + AName + '.png', w);
    finally
      w.Free;
    end;
    Log(Format('%s.png %dx%d', [AName, shot.Width, shot.Height]));
  finally
    shot.Free;
  end;
end;

initialization
  if SysUtils.GetEnvironmentVariable('TY_GALLERY_DIR') <> '' then
    Gallery := TGallery.Create(SysUtils.GetEnvironmentVariable('TY_GALLERY_DIR'));

finalization
  FreeAndNil(Gallery);

end.
