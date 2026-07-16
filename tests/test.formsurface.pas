unit test.formsurface;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Button, tyControls.FormSurface;
type
  { Option 1 — the surface is an ordinary streamed content container. Controls are ITS children (so
    graphic/windowless controls like TTyLabel paint on its canvas and stay visible), and it round-trips
    through the .lfm with its Align and its nested controls intact. }
  TFormSurfaceTest = class(TTestCase)
  published
    procedure TestSurfaceHostsControlsAcrossRoundTrip;
  end;

implementation

type
  THostForm = class(TForm)   // a streamable root that owns the design tree
  published
    Surface: TTyFormSurface;
  end;

procedure TFormSurfaceTest.TestSurfaceHostsControlsAcrossRoundTrip;
var
  Src, Dst: THostForm;
  Btn: TTyButton;
  MS: TMemoryStream;
  DstSurface: TTyFormSurface;
  Ctrl: TControl;
  I, BtnCount: Integer;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.Surface := TTyFormSurface.Create(Src);
    Src.Surface.Name := 'Surface';
    Src.Surface.Parent := Src;
    Src.Surface.Align := alClient;
    Btn := TTyButton.Create(Src);
    Btn.Name := 'Btn1';
    Btn.Parent := Src.Surface;          // a control hosted by the surface
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);

    DstSurface := Dst.FindComponent('Surface') as TTyFormSurface;
    AssertNotNull('surface survived the round-trip', DstSurface);
    AssertEquals('surface Align = alClient streamed', Ord(alClient), Ord(DstSurface.Align));
    BtnCount := 0;
    for I := 0 to DstSurface.ControlCount - 1 do
    begin
      Ctrl := DstSurface.Controls[I];
      if Ctrl is TTyButton then Inc(BtnCount);
    end;
    AssertEquals('button persisted as a child of the surface', 1, BtnCount);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

initialization
  { The reader instantiates streamed children by class name — register them. }
  RegisterClasses([TTyFormSurface, TTyButton]);
  RegisterTest(TFormSurfaceTest);
end.
