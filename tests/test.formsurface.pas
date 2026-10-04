unit test.formsurface;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Button, tyControls.Form, tyControls.FormSurface, tyControls.Controller,
  tyControls.Panel;
type
  { Option 1 — the surface is an ordinary streamed content container. Controls are ITS children (so
    graphic/windowless controls like TTyLabel paint on its canvas and stay visible), and it round-trips
    through the .lfm with its Align and its nested controls intact. }
  TFormSurfaceTest = class(TTestCase)
  published
    procedure TestSurfaceHostsControlsAcrossRoundTrip;
    procedure TestAReadFormKeepsItsSurfaceByClassNotName;
  end;

implementation

type
  THostForm = class(TTyForm)   // a streamable root; must be a TTyForm — the surface's parent always is
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

{ A form read from a .lfm knows its content surface by class, the way it knows one dropped on it:
  the designer calls it Surface, but a renamed one is still the surface -- and another control
  that happens to be called Surface is not. Loaded used to re-find it with FindComponent('Surface')
  and cast whatever came back, undoing the by-class wiring the reader had already done. (#22) }
procedure TFormSurfaceTest.TestAReadFormKeepsItsSurfaceByClassNotName;

  procedure RoundTrip(const AName: string; ADecoy: Boolean);
  var
    src, dst: TTyForm;
    s: TTyFormSurface;
    decoy: TTyPanel;
    ms: TMemoryStream;
    got: TComponent;
    ctl: TTyStyleController;
    what: string;
  begin
    what := 'a surface named ' + AName;
    if ADecoy then what := what + ', next to a panel named Surface';
    src := TTyForm.CreateNew(nil);
    dst := nil;
    ms := TMemoryStream.Create;
    try
      src.Name := 'F';
      s := TTyFormSurface.Create(src);
      s.Name := AName;
      s.Parent := src;
      s.Align := alClient;
      if ADecoy then
      begin
        decoy := TTyPanel.Create(src);
        decoy.Name := 'Surface';
        decoy.Parent := s;
      end;
      ms.WriteComponent(src);
      ms.Position := 0;
      dst := TTyForm.CreateNew(nil);
      ms.ReadComponent(dst);
      got := dst.FindComponent(AName);
      AssertTrue(what + ': the surface came back', got is TTyFormSurface);
      ctl := TTyStyleController.Create(dst);
      dst.Controller := ctl;
      AssertTrue(what + ': a Controller set after reading reaches the surface',
        TTyFormSurface(got).Controller = ctl);
      if ADecoy then
        AssertFalse(what + ': and not the panel that is merely called Surface',
          TTyPanel(dst.FindComponent('Surface')).Controller = ctl);
    finally
      ms.Free;
      dst.Free;
      src.Free;
    end;
  end;

begin
  RoundTrip('Surface', False);
  RoundTrip('Body', False);
  RoundTrip('Body', True);
end;

initialization
  { The reader instantiates streamed children by class name — register them. }
  RegisterClasses([TTyFormSurface, TTyButton]);
  RegisterTest(TFormSurfaceTest);
end.
