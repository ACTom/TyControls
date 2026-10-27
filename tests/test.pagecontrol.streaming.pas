unit test.pagecontrol.streaming;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Button, tyControls.TabSheet, tyControls.PageControl;
type
  TPageControlStreamingTest = class(TTestCase)
  private
    FChanges: Integer;
    procedure CountChange(Sender: TObject);
  published
    procedure TestRoundTripPreservesPagesAndChildren;
    { #145: a page control read from a form saved on another page fires neither OnChanging
      nor OnChange -- both ran before FormCreate -- and one on a form being destroyed fires no
      OnChange as its pages go. }
    procedure TestLoadingOnAnotherPageFiresNoChangeEvents;
    procedure TestDestroyingTheFormFiresNoPageChange;
  end;

implementation

type
  THostForm = class(TForm)   // a streamable root that owns the design tree
  published
    PC: TTyPageControl;
  end;

var
  GChanging, GChange: Integer;
  GCounting: Boolean;   // only the pager made by the reader counts

type
  { Counts its own change events from the moment it is read, before Loaded. }
  TCountingPageControl = class(TTyPageControl)
  private
    procedure CountChanging(Sender: TObject; ANewIndex: Integer; var AllowChange: Boolean);
    procedure CountChange(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TCountingPageControl.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Not for the one written out: the writer would look for these methods on the form. }
  if GCounting then
  begin
    OnChanging := @CountChanging;
    OnChange := @CountChange;
  end;
end;

procedure TCountingPageControl.CountChanging(Sender: TObject; ANewIndex: Integer;
  var AllowChange: Boolean);
begin
  Inc(GChanging);
end;

procedure TCountingPageControl.CountChange(Sender: TObject);
begin
  Inc(GChange);
end;

procedure TPageControlStreamingTest.CountChange(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TPageControlStreamingTest.TestLoadingOnAnotherPageFiresNoChangeEvents;
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'HostForm1';
    Src.PC := TCountingPageControl.Create(Src);
    Src.PC.Name := 'PC';
    Src.PC.Parent := Src;
    Src.PC.AddPage('One');
    Src.PC.AddPage('Two');
    Src.PC.AddPage('Three');
    Src.PC.ActivePageIndex := 2;
    MS.WriteComponent(Src);
    MS.Position := 0;
    GChanging := 0;
    GChange := 0;
    GCounting := True;
    try
      MS.ReadComponent(Dst);
    finally
      GCounting := False;
    end;
    AssertTrue('precondition: the read pager counts', Assigned(Dst.PC.OnChange));
    AssertEquals('precondition: read back on the saved page', 2, Dst.PC.ActivePageIndex);
    AssertEquals('no OnChanging while the form is read', 0, GChanging);
    AssertEquals('no OnChange either', 0, GChange);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

procedure TPageControlStreamingTest.TestDestroyingTheFormFiresNoPageChange;
var
  F: TForm;
  pc: TTyPageControl;
begin
  F := TForm.CreateNew(nil);
  pc := TTyPageControl.Create(F);
  pc.Parent := F;
  pc.AddPage('One');
  pc.AddPage('Two');
  pc.AddPage('Three');          // owned by the form, made last: freed first
  pc.ActivePageIndex := 2;
  FChanges := 0;
  pc.OnChange := @CountChange;
  F.Free;
  AssertEquals('no OnChange on a form being destroyed', 0, FChanges);
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
    Src.PC.Pages[0].TabVisible := False;   // a permission-hidden tab must stream
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
    AssertFalse('TabVisible = False survived', DstPC.Pages[0].TabVisible);
    AssertTrue('the default stayed unwritten and restores True', DstPC.Pages[1].TabVisible);
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
  RegisterClasses([TTyPageControl, TTyTabSheet, TTyButton, TCountingPageControl]);
  RegisterTest(TPageControlStreamingTest);
end.
