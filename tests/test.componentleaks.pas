unit test.componentleaks;
{$mode objfpc}{$H+}

{ Every registered component frees what it allocates.

  TTyStringGrid's constructor created two lists its destructor never freed (#16): two leaked
  blocks per grid, which heaptrc reports on exit and nothing in a test suite that does not run
  under heaptrc ever notices. This sweep asks every class on the palette the same question
  without heaptrc: build it on a form, free it, free the form -- a few times to warm the shared
  caches (theme styles, measurements, icon fonts) that are not leaks, then twenty more times,
  after which the heap must be no bigger than before.

  A fresh form each round, freed each round, because "freed by its owner" is not a leak: a
  container's children belong to the form, as the LCL has it (TWinControl.Destroy only unparents
  them), so a TTyGridPanel freed on a form that stays open leaves its cells to the form, which
  frees them when it closes. A form kept open across the rounds would count them as growth. }

interface

uses
  Classes, SysUtils, Forms, Controls, fpcunit, testregistry, test.designregistry;

type
  TComponentLeakTest = class(TTestCase)
  published
    procedure TestEveryRegisteredComponentFreesWhatItAllocates;
  end;

implementation

procedure TComponentLeakTest.TestEveryRegisteredComponentFreesWhatItAllocates;
var
  names, leaking: TStringList;
  i, k, swept: Integer;
  cls: TPersistentClass;
  before, after: PtrUInt;

  procedure BuildAndFree;
  var form: TForm; c: TComponent;
  begin
    form := TForm.CreateNew(nil);
    try
      form.SetBounds(0, 0, 400, 300);
      c := TComponentClass(cls).Create(form);
      if c is TControl then TControl(c).Parent := form;
      c.Free;
    finally
      form.Free;
    end;
  end;

begin
  names := TStringList.Create;
  leaking := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    AssertTrue('the design-registry parser found the palette', names.IndexOf('TTyButton') >= 0);
    swept := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or (not cls.InheritsFrom(TComponent)) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      try
        for k := 1 to 3 do BuildAndFree;
        before := GetFPCHeapStatus.CurrHeapUsed;
        for k := 1 to 20 do BuildAndFree;
        after := GetFPCHeapStatus.CurrHeapUsed;
        Inc(swept);
        if after > before then
          leaking.Add(Format('%s: the heap grew by %d bytes over twenty', [names[i],
            after - before]));
      except
        on E: Exception do
          leaking.Add(names[i] + ': ' + E.ClassName + ': ' + E.Message);
      end;
    end;
    AssertTrue(Format('the sweep must cover the palette, and it covered %d classes', [swept]),
      swept > 100);
    AssertEquals('components that do not free everything they allocate:' + LineEnding +
      leaking.Text, 0, leaking.Count);
  finally
    leaking.Free;
    names.Free;
  end;
end;

initialization
  RegisterTest(TComponentLeakTest);
end.
