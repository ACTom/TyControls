unit test.formwindowstate;

{$mode objfpc}{$H+}

{ #193: a TTyForm its chrome maximized -- the caption button, the title-bar double-click, a
  WindowState = wsMaximized at the first show -- says so in WindowState, as one the system
  maximized does: OnWindowStateChange fires, and WindowState := wsNormal restores it. }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, fpcunit, testregistry,
  {$IFDEF MSWINDOWS} Windows, {$ENDIF}
  tyControls.Form;

type
  TFormWindowStateTest = class(TTestCase)
  private
    FChanges: Integer;
    FSeen: TWindowState;
    procedure StateChanged(Sender: TObject);
    procedure MaximizeOnShow(Sender: TObject);
  protected
    procedure SetUp; override;
  published
    procedure TestTheButtonsMaximizeIsInWindowState;
    procedure TestWindowStateNormalUndoesTheButtonsMaximize;
    procedure TestTheSystemsMaximizeStillGoesBackThroughTheSystem;
    procedure TestTheButtonUndoesTheSystemsMaximizeThroughTheSystem;
    procedure TestTheButtonsMaximizeFiresOnWindowStateChange;
    procedure TestTheSystemsReportsKeepItMaximized;
    procedure TestAMinimizedFormComesBackNormal;
    procedure TestAFormShownMaximizedSaysSoWithoutAnEvent;
    procedure TestAMaximizeInOnShowIsTheEnginesOwn;
  end;

implementation

type
  TStateForm = class(TTyForm)
  public
    function Engine: TTyChromeEngine;
    procedure InjectResizing(AState: TWindowState);
  end;

function TStateForm.Engine: TTyChromeEngine;
begin
  Result := FEngine;
end;

procedure TStateForm.InjectResizing(AState: TWindowState);
begin
  Resizing(AState);
end;

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ A form with a title bar, at 10,10 400 x 300, not shown. }
function NewForm: TStateForm;
begin
  Result := TStateForm.CreateNew(nil);
  TTyTitleBar.Create(Result);
  Result.SetBounds(10, 10, 400, 300);
end;

{ Shown, off screen: a window the system shows, so the widgetset reports its size changes and
  LCL fires OnWindowStateChange. The engine's maximize brings it onto the screen. }
function NewShownForm: TStateForm;
begin
  Result := NewForm;
  Result.SetBounds(-4000, -4000, 400, 300);
  Result.Visible := True;
end;

procedure TFormWindowStateTest.SetUp;
begin
  NeedWidgetSet;
  FChanges := 0;
  FSeen := wsNormal;
end;

procedure TFormWindowStateTest.StateChanged(Sender: TObject);
begin
  Inc(FChanges);
  FSeen := TCustomForm(Sender).WindowState;
end;

procedure TFormWindowStateTest.MaximizeOnShow(Sender: TObject);
begin
  TStateForm(Sender).Engine.ToggleMaximize;
end;

procedure TFormWindowStateTest.TestTheButtonsMaximizeIsInWindowState;
var
  f: TStateForm;
begin
  f := NewForm;
  try
    f.Engine.ToggleMaximize;   // the caption button, the title-bar double-click
    AssertTrue('setup: the engine maximized it', f.Engine.Maximized);
    AssertFalse('setup: not the system', f.Engine.NativeMaximized);
    AssertEquals('WindowState says so', Ord(wsMaximized), Ord(f.WindowState));
    AssertEquals('read as a TCustomForm too', Ord(wsMaximized), Ord(TCustomForm(f).WindowState));
    f.Engine.ToggleMaximize;
    AssertEquals('restored, it says that', Ord(wsNormal), Ord(f.WindowState));
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestWindowStateNormalUndoesTheButtonsMaximize;
var
  f: TStateForm;
begin
  f := NewForm;
  try
    f.Engine.ToggleMaximize;
    f.WindowState := wsNormal;
    AssertFalse('restored', f.Engine.Maximized);
    AssertEquals('state', Ord(wsNormal), Ord(f.WindowState));
    AssertEquals('to where it was: left', 10, f.Left);
    AssertEquals('top', 10, f.Top);
    AssertEquals('width', 400, f.Width);
    AssertEquals('height', 300, f.Height);
    AssertTrue('the caption button offers maximize again', f.TitleBar.MaxButton.Kind = cbkMax);
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestTheSystemsMaximizeStillGoesBackThroughTheSystem;
var
  f: TStateForm;
begin
  f := NewForm;
  try
    f.Engine.SavedBounds := Types.Rect(500, 500, 600, 600);   // not this maximize's
    f.WindowState := wsMaximized;
    f.InjectResizing(wsMaximized);                      // Aero Snap, Win+Up
    AssertTrue('setup: the system''s maximize', f.Engine.NativeMaximized);
    f.WindowState := wsNormal;
    AssertEquals('the system''s to undo: the engine leaves the bounds', 10, f.Left);
    AssertEquals('state', Ord(wsNormal), Ord(f.WindowState));
  finally
    f.Free;
  end;
end;

{ Shown: the system's maximize is the system's to undo, and the caption button asks it to. It
  must still find the window maximized when it is asked. }
procedure TFormWindowStateTest.TestTheButtonUndoesTheSystemsMaximizeThroughTheSystem;
var
  f: TStateForm;
begin
  f := NewShownForm;
  try
    f.WindowState := wsMaximized;   // the system maximizes it
    AssertTrue('setup: the system''s maximize', f.Engine.NativeMaximized);
    f.Engine.ToggleMaximize;        // the caption button
    AssertEquals('state', Ord(wsNormal), Ord(f.WindowState));
    {$IFDEF MSWINDOWS}
    AssertFalse('the system restored it', IsZoomed(f.Handle));
    {$ENDIF}
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestTheButtonsMaximizeFiresOnWindowStateChange;
var
  f: TStateForm;
begin
  f := NewShownForm;
  try
    f.OnWindowStateChange := @StateChanged;
    f.Engine.ToggleMaximize;
    AssertEquals('maximized: OnWindowStateChange', 1, FChanges);
    AssertEquals('with the new state in', Ord(wsMaximized), Ord(FSeen));
    f.Engine.ToggleMaximize;
    AssertEquals('restored: again', 2, FChanges);
    AssertEquals('wsNormal', Ord(wsNormal), Ord(FSeen));
    f.Engine.ToggleMaximize;
    f.WindowState := wsNormal;
    AssertEquals('restored from code: again', 4, FChanges);
    AssertFalse('and restored', f.Engine.Maximized);
    AssertEquals('to where it was', -4000, f.Left);
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestTheSystemsReportsKeepItMaximized;
var
  f: TStateForm;
begin
  f := NewShownForm;
  try
    f.Engine.ToggleMaximize;
    f.OnWindowStateChange := @StateChanged;
    f.InjectResizing(wsNormal);   // what the widgetset says of the engine's SetBounds
    AssertEquals('still wsMaximized', Ord(wsMaximized), Ord(f.WindowState));
    AssertEquals('and no OnWindowStateChange', 0, FChanges);
    AssertTrue('the engine keeps its maximize', f.Engine.Maximized);
    f.InjectResizing(wsMinimized);   // the system minimized it
    AssertEquals('minimized', Ord(wsMinimized), Ord(f.WindowState));
    f.InjectResizing(wsNormal);      // and brought it back, as the engine left it
    AssertEquals('maximized again', Ord(wsMaximized), Ord(f.WindowState));
    AssertEquals('both changes heard', 2, FChanges);
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestAMinimizedFormComesBackNormal;
var
  f: TStateForm;
begin
  f := NewShownForm;
  try
    f.Engine.ToggleMaximize;
    f.WindowState := wsMinimized;
    {$IFDEF MSWINDOWS}
    AssertTrue('setup: minimized', IsIconic(f.Handle));
    {$ENDIF}
    f.WindowState := wsNormal;
    {$IFDEF MSWINDOWS}
    AssertFalse('back on the screen', IsIconic(f.Handle));
    {$ENDIF}
    AssertFalse('and not maximized', f.Engine.Maximized);
    AssertEquals('state', Ord(wsNormal), Ord(f.WindowState));
    AssertEquals('where it was', -4000, f.Left);
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestAFormShownMaximizedSaysSoWithoutAnEvent;
var
  f: TStateForm;
begin
  f := NewForm;
  try
    f.SetBounds(-4000, -4000, 400, 300);
    f.WindowState := wsMaximized;   // as the .lfm leaves it
    f.OnWindowStateChange := @StateChanged;
    f.Visible := True;
    AssertTrue('the engine maximized it', f.Engine.Maximized);
    AssertFalse('the system did not', f.Engine.NativeMaximized);
    AssertEquals('WindowState says so', Ord(wsMaximized), Ord(f.WindowState));
    AssertEquals('it was wsMaximized all along: no OnWindowStateChange', 0, FChanges);
  finally
    f.Free;
  end;
end;

procedure TFormWindowStateTest.TestAMaximizeInOnShowIsTheEnginesOwn;
var
  f: TStateForm;
begin
  f := NewForm;
  try
    f.SetBounds(-4000, -4000, 400, 300);
    f.OnShow := @MaximizeOnShow;
    f.Visible := True;
    AssertTrue('maximized', f.Engine.Maximized);
    AssertFalse('by the engine: the widgetset found wsNormal when it showed the window',
      f.Engine.NativeMaximized);
    AssertEquals('then WindowState said so', Ord(wsMaximized), Ord(f.WindowState));
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TFormWindowStateTest);
end.
