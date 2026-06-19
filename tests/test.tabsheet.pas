unit test.tabsheet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, TypInfo, fpcunit, testregistry,
  tyControls.TabSheet;
type
  TTabSheetTest = class(TTestCase)
  published
    procedure TestDesignControlStyleFlags;
    procedure TestCaptionPublished;
  end;

implementation

procedure TTabSheetTest.TestDesignControlStyleFlags;
var
  S: TTyTabSheet;
begin
  S := TTyTabSheet.Create(nil);
  try
    AssertTrue('csAcceptsControls',   csAcceptsControls   in S.ControlStyle);
    AssertTrue('csDesignFixedBounds', csDesignFixedBounds in S.ControlStyle);
    AssertTrue('csNoDesignVisible',   csNoDesignVisible   in S.ControlStyle);
    AssertTrue('csNoFocus',           csNoFocus           in S.ControlStyle);
    AssertEquals('alClient', Ord(alClient), Ord(S.Align));
  finally
    S.Free;
  end;
end;

procedure TTabSheetTest.TestCaptionPublished;
var
  S: TTyTabSheet;
begin
  S := TTyTabSheet.Create(nil);
  try
    AssertTrue('Caption is published', IsPublishedProp(S, 'Caption'));
    S.Caption := 'Page X';
    AssertEquals('Page X', S.Caption);
  finally
    S.Free;
  end;
end;

initialization
  RegisterTest(TTabSheetTest);
end.
