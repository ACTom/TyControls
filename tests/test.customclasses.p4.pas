unit test.customclasses.p4;
{$mode objfpc}{$H+}

{ Custom-class split, phase 4 (the non-visual components: controllers, icon fonts and image
  lists, hints and notifications, dialogs). Same fixture and checks as the earlier phases
  (TTyCustomClassesPhaseCase), minus the paint comparison -- nothing here paints itself:

  * THIRD-PARTY MIMICS: a TTyCustomXxx descendant that publishes two properties of its own
    choosing -- it can be created without an owner (T-a), publishes exactly its LCL root's
    names plus the two (T-b; the root is TComponent, or TCustomImageList for the image lists),
    streams those two and not a property it left out (T-c), streams nothing from a fresh
    instance (T-e), and reaches a public property through a TTyCustomXxx reference (T-v).
  * DERIVED COMPONENTS SEEN BY THEIR FAMILY: from 4.0 on a TTyLucideImageList is a
    TTyCustomVirtualImageList but no longer a TTyVirtualImageList; library code that meant "any
    virtual image list" asks for the custom class, and each such check has a test that fails
    when it is put back.
  * COMPONENT REFERENCES THE LCL WAY: a property that references a splittable component names
    its custom class (LCL's Images: TCustomImageList), so a third party's -- and the library's
    own derived -- component can be assigned to it. }

interface

uses
  Classes, SysUtils, TypInfo, Controls, Forms, Graphics,
  fpcunit, testregistry,
  test.customclasses, test.customclasses.p1,
  tyControls.Base, tyControls.Controller, tyControls.NativeStyler;

type
  TTyCustomClassesP4Test = class(TTyCustomClassesPhaseCase)
  published
    { Task 27: controllers }
    procedure TestThirdStyleController;
    procedure TestThirdNativeStyler;
  end;

  { --- third-party mimics ------------------------------------------------------------ }

  TThirdStyleController = class(TTyCustomStyleController)
  published
    property ThemeName;
    property Mode;
  end;

  TThirdNativeStyler = class(TTyCustomNativeStyler)
  published
    property Enabled;
    property ApplyFontSize;
  end;

implementation

{ T-a: a non-visual component is created without an owner just as well. }
procedure CheckCreatesWithoutOwner(AClass: TComponentClass);
var
  c: TComponent;
begin
  c := AClass.Create(nil);
  try
    TAssert.AssertNotNull('T-a: ' + AClass.ClassName + '.Create(nil)', c);
  finally
    c.Free;
  end;
end;

{ ------------------------------------------------------------------ Task 27: controllers }

procedure TTyCustomClassesP4Test.TestThirdStyleController;
var
  third, back: TThirdStyleController;
  c: TTyCustomStyleController;
begin
  CheckCreatesWithoutOwner(TThirdStyleController);
  third := TThirdStyleController.Create(FForm);
  CheckPublishesOnly(TThirdStyleController, ['ThemeName', 'Mode']);
  { ThemeName and ThemeFile are one source (setting either clears the other), so the property
    left out is Density. A name nobody registered is recorded all the same. }
  third.ThemeName := 'p4-unregistered-theme';
  third.Mode := 'dark';
  third.Density := tdModern;
  CheckStreamText(third, ['ThemeName', 'Mode'], 'Density');
  back := TThirdStyleController.Create(FForm);
  StreamInto(third, back);
  AssertEquals('T-c: ThemeName round-trips', 'p4-unregistered-theme', back.ThemeName);
  AssertEquals('T-c: Mode round-trips', 'dark', back.Mode);
  AssertTrue('T-c: the unpublished Density stayed at its default', back.Density = tdClassic);
  CheckFreshDefaults(TThirdStyleController, ['ThemeName', 'Mode']);
  c := third;
  c.HotReload := True;
  AssertTrue('T-v: HotReload is public through a TTyCustomStyleController reference',
    third.HotReload);
end;

procedure TTyCustomClassesP4Test.TestThirdNativeStyler;
var
  third, back: TThirdNativeStyler;
  c: TTyCustomNativeStyler;
begin
  CheckCreatesWithoutOwner(TThirdNativeStyler);
  third := TThirdNativeStyler.Create(FForm);
  CheckPublishesOnly(TThirdNativeStyler, ['Enabled', 'ApplyFontSize']);
  AssertTrue('the fresh styler is enabled (or the round trip proves nothing)', third.Enabled);
  third.Enabled := False;
  third.ApplyFontSize := True;
  third.ApplyFontName := True;
  CheckStreamText(third, ['Enabled', 'ApplyFontSize'], 'ApplyFontName');
  back := TThirdNativeStyler.Create(FForm);
  StreamInto(third, back);
  AssertFalse('T-c: Enabled round-trips', back.Enabled);
  AssertTrue('T-c: ApplyFontSize round-trips', back.ApplyFontSize);
  AssertFalse('T-c: the unpublished ApplyFontName stayed at its default', back.ApplyFontName);
  CheckFreshDefaults(TThirdNativeStyler, ['Enabled', 'ApplyFontSize']);
  c := third;
  c.Root := FForm;
  AssertTrue('T-v: Root is public through a TTyCustomNativeStyler reference', third.Root = FForm);
end;

initialization
  RegisterClasses([TThirdStyleController, TThirdNativeStyler]);
  RegisterTest(TTyCustomClassesP4Test);
end.
