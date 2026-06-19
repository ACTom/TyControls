unit test.pagecontrol.streaming;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Button, tyControls.TabSheet, tyControls.PageControl;
type
  TPageControlStreamingTest = class(TTestCase)
  published
    procedure TestRoundTripPreservesPagesAndChildren;
  end;

implementation

type
  THostForm = class(TForm)   // a streamable root that owns the design tree
  published
    PC: TTyPageControl;
  end;

procedure TPageControlStreamingTest.TestRoundTripPreservesPagesAndChildren;
var
  Src, Dst: THostForm;
  Pg2: TTyTabSheet;
  Btn: TTyButton;
  MS: TMemoryStream;
  I, BtnCount: Integer;
  DstPC: TTyPageControl;
  Ctrl: TControl;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.PC := TTyPageControl.Create(Src);
    Src.PC.Name := 'PC';
    Src.PC.Parent := Src;
    Src.PC.AddPage('One');
    Pg2 := Src.PC.AddPage('Two');
    Pg2.Name := 'PgTwo';
    Src.PC.ActivePageIndex := 1;
    Btn := TTyButton.Create(Src);
    Btn.Name := 'Btn1';
    Btn.Parent := Pg2;                 // a control "dropped" on page 2
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);             // read into a CreateNew'd root (no resource ctor)

    DstPC := Dst.FindComponent('PC') as TTyPageControl;
    AssertNotNull('page control survived', DstPC);
    AssertEquals('page count survived', 2, DstPC.PageCount);
    AssertEquals('captions survived', 'Two', DstPC.TabCaption(1));
    AssertEquals('active index survived', 1, DstPC.ActivePageIndex);
    BtnCount := 0;
    for I := 0 to DstPC.Pages[1].ControlCount - 1 do
    begin
      Ctrl := DstPC.Pages[1].Controls[I];
      if Ctrl is TTyButton then Inc(BtnCount);
    end;
    AssertEquals('button persisted as a child of page 2', 1, BtnCount);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

initialization
  { The reader instantiates streamed children by class name — register them. }
  RegisterClasses([TTyPageControl, TTyTabSheet, TTyButton]);
  RegisterTest(TPageControlStreamingTest);
end.
