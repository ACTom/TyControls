unit test.tabsheet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, TypInfo, fpcunit, testregistry,
  tyControls.TabSheet, tyControls.PageControl;
type
  TTabSheetTest = class(TTestCase)
  published
    procedure TestDesignControlStyleFlags;
    procedure TestCaptionPublished;
    procedure TestTabCaptionIsTheStripsSizeNotThePages;
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

procedure TTabSheetTest.TestTabCaptionIsTheStripsSizeNotThePages;
{ The size-floor pass asked whether a clipped TAB caption should make TTyTabSheet publish a
  floor the way the captioned controls now do. It must not, and this pins why.

  A page never draws its Caption: TTyCustomTabStrip does, into FHeaderRects[i], which is
  Rect(x, 0, x + w, TabHPx) — the header BAND — with tlCenter and clipping on. So the box
  that can eat a tab caption's ink is TabHeight, and the page is the alClient BODY below that
  band: its height is the container's minus the band, and has nothing to do with the text.
  Flooring the page at its own caption would clamp the body of every page to a number about
  the tab label. Horizontally the strip already floors itself — a header is the measured
  caption plus 2x --tab-padding — so only the band's height is a request nobody checks.

  This asserts the decision: a longer tab label moves the header, never the page. }
var
  F: TForm;
  PC: TTyPageControl;
  S: TTyTabSheet;
  w, h: Integer;
begin
  F := TForm.CreateNew(nil);
  try
    PC := TTyPageControl.Create(F);
    PC.Parent := F;
    PC.Font.PixelsPerInch := 96;
    PC.SetBounds(0, 0, 300, 200);
    S := PC.AddPage('新建');
    w := S.Width;
    h := S.Height;

    S.Caption := '一个长得多的中文标签,长到任何一条标签栏都得为它变宽';
    AssertEquals('a longer tab label does not resize the page', w, S.Width);
    AssertEquals('...on either axis', h, S.Height);
    AssertEquals('and the page publishes no height floor of its own',
      0, S.Constraints.MinHeight);
    AssertEquals('nor a width one', 0, S.Constraints.MinWidth);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TTabSheetTest);
end.
