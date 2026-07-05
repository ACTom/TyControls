unit test.linklabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, fpcunit, testregistry,
  tyControls.LinkLabel;
type
  TLinkLabelTest = class(TTestCase)
  published
    procedure TestUnderlineRect;
    procedure TestSmoke;
  end;
implementation

procedure TLinkLabelTest.TestUnderlineRect;
var r: TRect;
begin
  // Left-aligned: line starts at content left, 1px tall, dropped 3px from bottom.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taLeftJustify);
  AssertEquals('left.left',   10, r.Left);
  AssertEquals('left.right',  50, r.Right);
  AssertEquals('left.top',    17, r.Top);
  AssertEquals('left.bottom', 18, r.Bottom);

  // Right-aligned: line ends at content right.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taRightJustify);
  AssertEquals('right.left',  70, r.Left);
  AssertEquals('right.right', 110, r.Right);

  // Centred: symmetric inset ((100-40)/2 = 30 -> 10+30 = 40).
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 40, 3, taCenter);
  AssertEquals('center.left',  40, r.Left);
  AssertEquals('center.right', 80, r.Right);

  // Width wider than content clamps to the content width.
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), 500, 3, taLeftJustify);
  AssertEquals('clamp.left',  10, r.Left);
  AssertEquals('clamp.right', 110, r.Right);

  // Negative width clamps to 0 (empty line).
  r := TyLinkUnderlineRect(Rect(10, 0, 110, 20), -5, 3, taLeftJustify);
  AssertEquals('neg.left',  10, r.Left);
  AssertEquals('neg.right', 10, r.Right);
end;

procedure TLinkLabelTest.TestSmoke;
var lbl: TTyLinkLabel;
begin
  lbl := TTyLinkLabel.Create(nil);
  try
    lbl.Caption := 'Visit homepage';
    lbl.URL := 'https://example.com';
    lbl.AutoOpen := True;
    lbl.Alignment := taCenter;
    lbl.Layout := tlBottom;
    AssertEquals('caption round-trips', 'Visit homepage', lbl.Caption);
    AssertEquals('url round-trips', 'https://example.com', lbl.URL);
  finally
    lbl.Free;
  end;
end;

initialization
  RegisterTest(TLinkLabelTest);
end.
