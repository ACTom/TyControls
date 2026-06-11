unit test.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types;

type
  TTestTypes = class(TTestCase)
  published
    procedure TestTyRGB;
    procedure TestTyRGBA;
    procedure TestTyAlphaOf;
    procedure TestTyChannelOf;
    procedure TestTransparentConst;
    procedure TestEmptyStyleSet;
  end;

implementation

procedure TTestTypes.TestTyRGB;
begin
  AssertEquals('opaque red', TTyColor($FFFF0000), TyRGB(255, 0, 0));
  AssertEquals('opaque green', TTyColor($FF00FF00), TyRGB(0, 255, 0));
end;

procedure TTestTypes.TestTyRGBA;
begin
  AssertEquals('half-alpha blue', TTyColor($800000FF), TyRGBA(0, 0, 255, $80));
end;

procedure TTestTypes.TestTyAlphaOf;
begin
  AssertEquals('alpha byte', Byte($80), TyAlphaOf(TTyColor($80112233)));
end;

procedure TTestTypes.TestTyChannelOf;
begin
  AssertEquals('red', Byte($11), TyRedOf(TTyColor($FF112233)));
  AssertEquals('green', Byte($22), TyGreenOf(TTyColor($FF112233)));
  AssertEquals('blue', Byte($33), TyBlueOf(TTyColor($FF112233)));
end;

procedure TTestTypes.TestTransparentConst;
begin
  AssertEquals('transparent', TTyColor($00000000), tyTransparent);
end;

procedure TTestTypes.TestEmptyStyleSet;
var
  s: TTyStyleSet;
begin
  s := EmptyStyleSet;
  AssertTrue('present empty', s.Present = []);
  AssertEquals('opacity default', Single(1.0), s.Opacity, 0.0001);
  AssertTrue('bg none', s.Background.Kind = tfkNone);
end;

initialization
  RegisterTest(TTestTypes);
end.
