unit test.controller.changelistener;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Controller;
type
  TChangeListenerTest = class(TTestCase)
  private
    FHits: Integer;
    procedure OnCtlChanged(Sender: TObject);
  published
    procedure TestListenerFiresOnChanged;
    procedure TestRemovedListenerDoesNotFire;
  end;

implementation

procedure TChangeListenerTest.OnCtlChanged(Sender: TObject);
begin
  Inc(FHits);
end;

procedure TChangeListenerTest.TestListenerFiresOnChanged;
var Ctl: TTyStyleController;
begin
  FHits := 0;
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.AddChangeListener(@OnCtlChanged);
    Ctl.Changed;
    Ctl.Changed;
    AssertEquals('listener fired once per Changed', 2, FHits);
  finally
    Ctl.Free;
  end;
end;

procedure TChangeListenerTest.TestRemovedListenerDoesNotFire;
var Ctl: TTyStyleController;
begin
  FHits := 0;
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.AddChangeListener(@OnCtlChanged);
    Ctl.RemoveChangeListener(@OnCtlChanged);
    Ctl.Changed;
    AssertEquals('removed listener never fires', 0, FHits);
  finally
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TChangeListenerTest);
end.
