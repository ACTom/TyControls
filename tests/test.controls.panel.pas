unit test.controls.panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Graphics, Forms, Controls, StdCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Panel;
type
  TTyPanelTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TTyPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaultCaptionEmpty;
    procedure TestImplementsStyleable;
    procedure TestHostsChild;
    procedure TestPaintSmoke;
    procedure TestAlignmentMovesCaptionInk;
    procedure TestIsDesignerContainer;
    procedure TestVerticalAlignmentIsLclsExactShape;
    procedure TestVerticalAlignmentLoadsAnLclLfmAndRefusesTheOldDevIdentifier;
  end;
implementation
type
  TPanelAccess = class(TTyPanel)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
procedure TPanelAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
procedure TTyPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TTyPanel.Create(FForm);
  FPanel.Parent := FForm;
end;
procedure TTyPanelTest.TearDown;
begin
  FForm.Free;
end;
procedure TTyPanelTest.TestTypeKey;
begin
  AssertEquals('TyPanel', FPanel.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestDefaultCaptionEmpty;
begin
  AssertEquals('', FPanel.Caption);
end;
procedure TTyPanelTest.TestImplementsStyleable;
var
  Styleable: ITyStyleable;
begin
  AssertTrue('TTyPanel must support ITyStyleable',
    Supports(FPanel, ITyStyleable, Styleable));
  AssertEquals('TyPanel', Styleable.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FPanel);
  Child.Parent := FPanel;
  AssertSame('child parent must be the panel', FPanel, Child.Parent);
  AssertEquals('panel must report one child control', 1, FPanel.ControlCount);
end;
procedure TTyPanelTest.TestPaintSmoke;
var
  Acc: TPanelAccess;
  Bmp: TBitmap;
begin
  Acc := TPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Caption := 'Panel';
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 60);
    Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 120, 60), 96);
    AssertTrue('panel RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;
procedure TTyPanelTest.TestAlignmentMovesCaptionInk;
  function InkCentroidX(A: TAlignment): Double;
  var P: TPanelAccess; bmp: TBitmap; reread: TBGRABitmap; x,y,n: Integer; sx: Double; px: TBGRAPixel;
  begin
    P := TPanelAccess.Create(nil);
    bmp := TBitmap.Create;
    try
      P.Caption := 'Hi'; P.Alignment := A; P.Font.PixelsPerInch := 96;
      bmp.PixelFormat := pf32bit; bmp.SetSize(200, 30);
      bmp.Canvas.Brush.Color := clWhite; bmp.Canvas.FillRect(0,0,200,30);
      P.SmokeRender(bmp.Canvas, Rect(0,0,200,30), 96);
      reread := TBGRABitmap.Create(bmp);
      try
        sx := 0; n := 0;
        for x := 0 to 199 do for y := 4 to 26 do
        begin px := reread.GetPixel(x,y);
          if (px.red<160) and (px.green<160) then begin sx := sx + x; Inc(n); end; end;
        if n = 0 then Result := -1 else Result := sx / n;
      finally reread.Free; end;
    finally bmp.Free; P.Free; end;
  end;
var cl, cr: Double;
begin
  cl := InkCentroidX(taLeftJustify);
  cr := InkCentroidX(taRightJustify);
  AssertTrue('left caption has ink', cl > 0);
  AssertTrue('right-aligned caption ink is further right than left-aligned', cr > cl + 20);
end;
procedure TTyPanelTest.TestIsDesignerContainer;
begin
  // csAcceptsControls makes the IDE designer drop child controls INTO the panel.
  AssertTrue('panel is a designer container', csAcceptsControls in FPanel.ControlStyle);
end;

{ The TYPE is the parity claim. TCustomPanel declares
    VerticalAlignment: TVerticalAlignment ... default taVerticalCenter  (extctrls.pp:1154)
  over the RTL enum (taAlignTop, taAlignBottom, taVerticalCenter) from classesh.inc:94.
  Ours shipped in-dev (4e3376a, never released) typed Graphics.TTextLayout instead -- so
  `P.VerticalAlignment := taAlignBottom` did not compile and an .lfm written by a real
  TPanel did not load. Same name, wrong meaning, is the collision class this pass removes. }
procedure TTyPanelTest.TestVerticalAlignmentIsLclsExactShape;
var
  pi: PPropInfo;
begin
  pi := GetPropInfo(TTyPanel, 'VerticalAlignment');
  AssertTrue('published', pi <> nil);
  AssertEquals('typed with the RTL''s TVerticalAlignment, as TCustomPanel is',
    'TVerticalAlignment', pi^.PropType^.Name);
  { The default DIRECTIVE stores an ordinal, so the enum's ordinals are API.
    taVerticalCenter is 2 in the RTL; if either assertion ever moves, every default
    already relied on by a streamed .lfm moves with it. }
  AssertEquals('default clause = Ord(taVerticalCenter)', Ord(taVerticalCenter), pi^.Default);
  AssertEquals('which is ordinal 2 in the RTL enum', 2, Ord(taVerticalCenter));
  AssertTrue('a fresh panel reads the default', FPanel.VerticalAlignment = taVerticalCenter);
end;

{ Both directions of the retype's compatibility decision, pinned:
  - an .lfm written by an LCL/Delphi TPanel (`taAlignBottom`) now LOADS -- the point;
  - an .lfm saved by an in-dev build of THIS library (`tlBottom`, the three days the
    property was mistyped) fails LOUDLY, not silently-as-centre. Loud is the acceptable
    half of the trade; a silent reinterpretation would not be. }
procedure TTyPanelTest.TestVerticalAlignmentLoadsAnLclLfmAndRefusesTheOldDevIdentifier;

  function LoadFragment(const AValueIdent: string; APanel: TTyPanel): Boolean;
  var
    txt: TStringStream;
    bin: TMemoryStream;
  begin
    txt := TStringStream.Create(
      'object P: TTyPanel' + LineEnding +
      '  VerticalAlignment = ' + AValueIdent + LineEnding +
      'end');
    bin := TMemoryStream.Create;
    try
      Result := True;
      try
        ObjectTextToBinary(txt, bin);
        bin.Position := 0;
        bin.ReadComponent(APanel);
      except
        Result := False;   // the reader refused the identifier
      end;
    finally
      bin.Free;
      txt.Free;
    end;
  end;

var
  P: TTyPanel;
begin
  P := TTyPanel.Create(nil);
  try
    AssertTrue('an LCL .lfm value (taAlignBottom) must load',
      LoadFragment('taAlignBottom', P));
    AssertTrue('...and land on the property', P.VerticalAlignment = taAlignBottom);
  finally P.Free; end;

  P := TTyPanel.Create(nil);
  try
    AssertFalse('the mistyped dev identifier (tlBottom) must FAIL to read -- loudly, '
      + 'never silently reinterpreted', LoadFragment('tlBottom', P));
  finally P.Free; end;
end;

initialization
  RegisterTest(TTyPanelTest);
  { .lfm 文本要能被 ObjectTextToBinary 认出类名。 }
  RegisterClass(TTyPanel);
end.
