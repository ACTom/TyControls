unit test.danglingrefs;
{$mode objfpc}{$H+}

{ A component that points at another one must let go of it when that one is freed, whoever owns it.

  A published reference to another component (Controller, Root, IconFont, Images, ...) is safe
  only if the holder asks the target for a free notification. Without one, the holder hears of
  the target's death only through its owner's broadcast, and that reaches it only when the two
  share an owner. Put the target on another form, or create it with no owner, free it, and the
  holder keeps a pointer to freed memory: TTyBalloonHint.ShowAt then reads the freed controller's
  Model, and the IDE reads it as soon as the form is saved. TTyBalloonHint.Controller,
  TTyHint.Controller and TTyNativeStyler.Root all did this.

  The other direction is a change list. TTyCharImage and TTyRibbonGallery put a method on their
  icon font's change list and never took it off: free the control while the font lives (a child
  form closed with caFree, a control deleted in the designer) and the next change to the font
  calls into freed memory.

  Both sweeps take their population from the palette, so a class added later is covered without
  being named here. }

interface

uses
  Classes, SysUtils, TypInfo, Forms, Controls, fpcunit, testregistry, test.designregistry,
  tyControls.IconFont, tyControls.ImageCollection;

type
  TDanglingRefsTest = class(TTestCase)
  published
    procedure TestEveryReferenceLetsGoOfAComponentFreedElsewhere;
    procedure TestAnIconFontOutlivesEveryControlThatWatchedIt;
    procedure TestAWatcherFreedBeforeTheIconFontLeavesItsChangeList;
    procedure TestAWatcherFreedBeforeTheImageListLeavesItsChangeList;
    procedure TestAWatchedIconFontCanBeFreedWhileItsFormLives;
    procedure TestAWatchedImageListCanBeFreedWhileItsFormLives;
  end;

implementation

{ Freed memory, poisoned and held back. Between BeginPoison and EndPoison a freed block is filled
  with $7F and kept off the heap, so a read through a dangling pointer meets $7F7F... and faults
  every time -- instead of meeting whatever the heap put there next, which is often a live object
  and a silent pass. $7F and not the usual $CC: as a pointer either is outside the address space,
  but as a count $CC... is negative, so a freed list walked from Count - 1 down to 0 never reads
  anything and the test passes over the very use it is there to catch. EndPoison hands the blocks
  back. }
const
  CQuarantineMax = 16384;
var
  GOldMM: TMemoryManager;
  GQuarantine: array[0..CQuarantineMax - 1] of Pointer;
  GQuarantined: Integer;

function PoisonFreemem(p: Pointer): PtrUInt;
begin
  if p = nil then Exit(0);
  if GQuarantined >= CQuarantineMax then Exit(GOldMM.Freemem(p));
  Result := GOldMM.MemSize(p);
  FillChar(p^, Result, $7F);
  GQuarantine[GQuarantined] := p;
  Inc(GQuarantined);
end;

function PoisonFreememSize(p: Pointer; ASize: PtrUInt): PtrUInt;
begin
  Result := PoisonFreemem(p);
end;

procedure BeginPoison;
var
  mm: TMemoryManager;
begin
  GetMemoryManager(GOldMM);
  mm := GOldMM;
  mm.Freemem := @PoisonFreemem;
  mm.FreememSize := @PoisonFreememSize;
  GQuarantined := 0;
  SetMemoryManager(mm);
end;

procedure EndPoison;
var
  i: Integer;
begin
  SetMemoryManager(GOldMM);
  for i := 0 to GQuarantined - 1 do
    GOldMM.Freemem(GQuarantine[i]);
  GQuarantined := 0;
end;

{ A sub-component the holder made for itself is part of the holder, not a reference to set. }
function IsOwnPart(AHolder: TComponent; AValue: TObject): Boolean;
begin
  Result := (AValue is TComponent) and ((TComponent(AValue).Owner = AHolder)
    or (csSubComponent in TComponent(AValue).ComponentStyle));
end;

function PlaceOn(AClass: TComponentClass; AForm: TForm): TComponent;
begin
  Result := AClass.Create(AForm);
  if Result is TControl then TControl(Result).Parent := AForm;
end;

procedure TDanglingRefsTest.TestEveryReferenceLetsGoOfAComponentFreedElsewhere;
var
  names, kept: TStringList;
  i, j, n, checked: Integer;
  cls: TPersistentClass;
  props: PPropList;
  pi: PPropInfo;
  tcls: TClass;
  home, elsewhere: TForm;
  c, tgt: TComponent;
begin
  names := TStringList.Create;
  kept := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    AssertTrue('the design-registry parser found the palette', names.IndexOf('TTyButton') >= 0);
    checked := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or (not cls.InheritsFrom(TComponent)) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      n := GetPropList(cls, props);
      try
        for j := 0 to n - 1 do
        begin
          pi := props^[j];
          if (pi^.PropType^.Kind <> tkClass) or (pi^.SetProc = nil) then Continue;
          tcls := GetTypeData(pi^.PropType)^.ClassType;
          if (not tcls.InheritsFrom(TComponent)) or tcls.InheritsFrom(TCustomForm) then Continue;
          { The target lives on ANOTHER form, so the owner's broadcast cannot reach the holder:
            only a free notification can. }
          home := TForm.CreateNew(nil);
          elsewhere := TForm.CreateNew(nil);
          try
            try
              c := PlaceOn(TComponentClass(cls), home);
              if IsOwnPart(c, GetObjectProp(c, pi)) then Continue;
              tgt := nil;
              try
                tgt := PlaceOn(TComponentClass(tcls), elsewhere);
                SetObjectProp(c, pi, tgt);
              except
                tgt := nil;   // a target this property refuses is not a reference it holds
              end;
              if (tgt = nil) or (GetObjectProp(c, pi) <> tgt) then Continue;
              Inc(checked);
              tgt.Free;
              if GetObjectProp(c, pi) <> nil then
                kept.Add(Format('%s.%s still points at the freed %s',
                  [cls.ClassName, pi^.Name, tcls.ClassName]));
            except
              on E: Exception do
                kept.Add(Format('%s.%s: %s: %s', [cls.ClassName, pi^.Name, E.ClassName, E.Message]));
            end;
          finally
            try
              home.Free;
            except
              on E: Exception do
                kept.Add(Format('%s.%s, freeing the holder''s form: %s: %s',
                  [cls.ClassName, pi^.Name, E.ClassName, E.Message]));
            end;
            try
              elsewhere.Free;
            except
              on E: Exception do
                kept.Add(Format('%s.%s, freeing the target''s form: %s: %s',
                  [cls.ClassName, pi^.Name, E.ClassName, E.Message]));
            end;
          end;
        end;
      finally
        FreeMem(props);
      end;
    end;
    AssertTrue(Format('the sweep must reach the palette''s references, and it reached %d',
      [checked]), checked > 100);
    AssertEquals('references that keep pointing at a component freed on another form:' +
      LineEnding + kept.Text, 0, kept.Count);
  finally
    kept.Free;
    names.Free;
  end;
end;

procedure TDanglingRefsTest.TestAnIconFontOutlivesEveryControlThatWatchedIt;
var
  names, crashed: TStringList;
  i, j, n, checked: Integer;
  cls: TPersistentClass;
  props: PPropList;
  pi: PPropInfo;
  tcls: TClass;
  home, elsewhere: TForm;
  c: TComponent;
  font: TTyIconFont;
begin
  names := TStringList.Create;
  crashed := TStringList.Create;
  try
    CollectRegisteredClassNames(names);
    checked := 0;
    for i := 0 to names.Count - 1 do
    begin
      cls := GetClass(names[i]);
      if (cls = nil) or (not cls.InheritsFrom(TComponent)) then Continue;
      if cls.InheritsFrom(TCustomForm) then Continue;
      n := GetPropList(cls, props);
      try
        for j := 0 to n - 1 do
        begin
          pi := props^[j];
          if (pi^.PropType^.Kind <> tkClass) or (pi^.SetProc = nil) then Continue;
          { Since the custom-class split (#8) the properties are typed TTyCustomIconFont, and a
            TTyIconFont is one: any property that can hold the font the sweep hands it. }
          tcls := GetTypeData(pi^.PropType)^.ClassType;
          if not (tcls.InheritsFrom(TTyCustomIconFont) and TTyIconFont.InheritsFrom(tcls)) then
            Continue;
          home := TForm.CreateNew(nil);
          elsewhere := TForm.CreateNew(nil);
          try
            font := TTyIconFont.Create(elsewhere);
            c := PlaceOn(TComponentClass(cls), home);
            SetObjectProp(c, pi, font);
            if GetObjectProp(c, pi) <> font then Continue;
            Inc(checked);
            BeginPoison;
            try
              try
                c.Free;
                { Every way a font announces a change goes through one Changed; a glyph mapped
                  at run time is the plainest. }
                font.MapGlyph('probe', $41);
              except
                on E: Exception do
                  crashed.Add(Format('%s.%s: %s: %s',
                    [cls.ClassName, pi^.Name, E.ClassName, E.Message]));
              end;
            finally
              EndPoison;
            end;
          finally
            home.Free;
            elsewhere.Free;
          end;
        end;
      finally
        FreeMem(props);
      end;
    end;
    AssertTrue(Format('the sweep must reach the icon-font holders, and it reached %d',
      [checked]), checked >= 2);
    AssertEquals('holders that, once freed, are still called when their icon font changes:' +
      LineEnding + crashed.Text, 0, crashed.Count);
  finally
    crashed.Free;
    names.Free;
  end;
end;

{ The change lists themselves, for a watcher that is not one of ours: an application's own
  component that follows a font or an image list the way the controls do -- a method on the list
  plus a free notification -- is taken off when it is freed. The count is global, not a field of
  the watcher, so the call it counts cannot itself fault on the freed watcher. }
type
  TChangeWatcher = class(TComponent)
  public
    procedure Changed(Sender: TObject);
  end;

var
  GWatcherCalls: Integer;

procedure TChangeWatcher.Changed(Sender: TObject);
begin
  Inc(GWatcherCalls);
end;

procedure TDanglingRefsTest.TestAWatcherFreedBeforeTheIconFontLeavesItsChangeList;
var
  font: TTyIconFont;
  w: TChangeWatcher;
begin
  font := TTyIconFont.Create(nil);
  try
    w := TChangeWatcher.Create(nil);
    font.AddHandlerOnChange(@w.Changed);
    font.FreeNotification(w);
    GWatcherCalls := 0;
    font.MapGlyph('a', $41);
    AssertEquals('a live watcher hears the change', 1, GWatcherCalls);
    w.Free;
    font.MapGlyph('b', $42);
    AssertEquals('a freed watcher is no longer called', 1, GWatcherCalls);
  finally
    font.Free;
  end;
end;

procedure TDanglingRefsTest.TestAWatcherFreedBeforeTheImageListLeavesItsChangeList;
var
  list: TTyVirtualImageList;
  w: TChangeWatcher;
begin
  list := TTyVirtualImageList.Create(nil);
  try
    w := TChangeWatcher.Create(nil);
    list.AddHandlerOnChange(@w.Changed);
    list.FreeNotification(w);
    GWatcherCalls := 0;
    list.GlyphColor := $FF102030;
    AssertEquals('a live watcher hears the change', 1, GWatcherCalls);
    w.Free;
    list.GlyphColor := $FF405060;
    AssertEquals('a freed watcher is no longer called', 1, GWatcherCalls);
  finally
    list.Free;
  end;
end;

{ The list's own end. Freeing a component while its form stays open ends in the owner telling
  every component it owns -- the dying one included -- and the font's Notification answers that by
  clearing a dying component's methods off its change list. The list was already freed by then, and
  only nil-ing it keeps that read off freed memory. (Poisoned, so the read faults rather than finding
  a block the heap has not reused yet.) }
procedure TDanglingRefsTest.TestAWatchedIconFontCanBeFreedWhileItsFormLives;
var
  form: TForm;
  font: TTyIconFont;
  w: TChangeWatcher;
begin
  form := TForm.CreateNew(nil);
  w := TChangeWatcher.Create(nil);
  try
    font := TTyIconFont.Create(form);
    font.AddHandlerOnChange(@w.Changed);
    font.FreeNotification(w);
    BeginPoison;
    try
      font.Free;
    finally
      EndPoison;
    end;
    AssertEquals('the form let go of the font', 0, form.ComponentCount);
  finally
    w.Free;
    form.Free;
  end;
end;

procedure TDanglingRefsTest.TestAWatchedImageListCanBeFreedWhileItsFormLives;
var
  form: TForm;
  list: TTyVirtualImageList;
  w: TChangeWatcher;
begin
  form := TForm.CreateNew(nil);
  w := TChangeWatcher.Create(nil);
  try
    list := TTyVirtualImageList.Create(form);
    list.AddHandlerOnChange(@w.Changed);
    list.FreeNotification(w);
    BeginPoison;
    try
      list.Free;
    finally
      EndPoison;
    end;
    AssertEquals('the form let go of the list', 0, form.ComponentCount);
  finally
    w.Free;
    form.Free;
  end;
end;

initialization
  RegisterTest(TDanglingRefsTest);
end.
