unit test.treeview.streaming;
{ E3: verify that Options (a published set property) round-trips through the
  LCL component stream so that an LFM with Options=[toMultiSelect,...] restores
  correctly on load. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.TreeView;
type
  TTreeViewStreamingTest = class(TTestCase)
  published
    procedure TestOptionsRoundTrip;
  end;

implementation

type
  THostForm = class(TForm)
  published
    TV: TTyTreeView;
  end;

procedure TTreeViewStreamingTest.TestOptionsRoundTrip;
{ Write a TTyTreeView with Options=[toMultiSelect,toCheckSupport,toFullRowSelect,
  toAutoTristateTracking] into a memory stream; read it into a fresh form;
  assert the Options set survived intact. }
const
  WantOpts: TTyTreeOptions =
    [toMultiSelect, toCheckSupport, toFullRowSelect, toAutoTristateTracking];
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
  DstTV: TTyTreeView;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS  := TMemoryStream.Create;
  try
    Src.Name   := 'HostFormTV1';
    Src.TV     := TTyTreeView.Create(Src);
    Src.TV.Name   := 'TV';
    Src.TV.Parent := Src;
    Src.TV.Options := WantOpts;
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);

    DstTV := Dst.FindComponent('TV') as TTyTreeView;
    AssertNotNull('TTyTreeView survived stream round-trip', DstTV);
    AssertTrue('toMultiSelect survived',
      toMultiSelect in DstTV.Options);
    AssertTrue('toCheckSupport survived',
      toCheckSupport in DstTV.Options);
    AssertTrue('toFullRowSelect survived',
      toFullRowSelect in DstTV.Options);
    AssertTrue('toAutoTristateTracking survived',
      toAutoTristateTracking in DstTV.Options);
    AssertTrue('no extra bits: options sets are equal',
      DstTV.Options = WantOpts);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

initialization
  RegisterClasses([TTyTreeView]);
  RegisterTest(TTreeViewStreamingTest);
end.
