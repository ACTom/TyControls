unit test.fieldpad;
{$mode objfpc}{$H+}

{ #103: a text field's text starts as far in from the left border as the drop V keeps from the
  right one. The fields took --pad-control (4px, which check boxes, tabs and menus share) or a
  literal 4px, and the date picker its own 4px 6px: in a combo box the V sat 10px from the right
  edge and the text 5px from the left, and five fields stacked in a form started their text in
  three different columns. They now take --pad-field (4px 9px; 8px 12px at modern density).

  These pin:
  - on the stock theme every field's text ink starts 10px in (9..11, the glyph's own bearing);
  - the built-in 'default' theme (auto.tycss, which restates the field rules) does the same;
  - the modern density pack moves them together, to 13;
  - one token reaches every field in every bundled base theme, so a theme or an app retunes
    all of them with one line. }

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, DateUtils, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  test.dpi.support,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.Form,
  tyControls.BuiltinThemes, tyControls.Edit, tyControls.ComboBox, tyControls.ComboEdit,
  tyControls.TreeSelect, tyControls.SpinEdit, tyControls.Cascader, tyControls.DateTimePicker;

type
  TFieldPadTest = class(TTestCase)
  private
    function TextLeft(AKind: Integer; const ATheme: string; ADensity: TTyDensity): Integer;
    procedure CheckAll(const AWhat, ATheme: string; ADensity: TTyDensity; ALo, AHi: Integer);
  published
    procedure TestEveryFieldStartsItsTextTenPxIn;
    procedure TestTheBuiltinDefaultThemeToo;
    procedure TestModernDensityMovesThemTogether;
    procedure TestOneTokenReachesEveryFieldInEveryBundledTheme;
  end;

implementation

const
  KEdit = 0; KCombo = 1; KComboEdit = 2; KTreeSelect = 3; KSpin = 4; KCascader = 5; KPicker = 6;
  KindName: array[KEdit..KPicker] of string = ('edit', 'combo box', 'combo edit',
    'tree select', 'spin edit', 'cascader', 'date picker');
  FieldKeys: array[0..4] of string = ('TyEdit', 'TyComboBox', 'TySpinEdit', 'TyCascader',
    'TyDateTimePicker');

{ The leftmost column of the field's text, painted headless at 96 PPI on a 220x40 field. The
  text is whatever the control shows first ('H', the spin edit's 8, the date's first digit, the
  tree select's hint), found as the first pixel left to right in the middle band that differs
  from the field's own face at x=2 -- inside the 1px border, before any padding this tests. }
function TFieldPadTest.TextLeft(AKind: Integer; const ATheme: string;
  ADensity: TTyDensity): Integer;
const
  W = 220;
  H = 40;
var
  ctl: TTyStyleController;
  host: TTyForm;
  c: TControl;
  cb: TTyComboBox;
  ce: TTyComboEdit;
  ts: TTyTreeSelect;
  sp: TTySpinEdit;
  cas: TTyCascader;
  dt: TTyDateTimePicker;
  ed: TTyEdit;
  path: TTyCascaderPath;
  shot: TBitmap;
  b: TBGRABitmap;
  face, px: TBGRAPixel;
  x, y: Integer;
begin
  Result := -1;
  ctl := TTyStyleController.Create(nil);
  host := TTyForm.CreateNew(nil);
  shot := nil;
  try
    ctl.LoadThemeCss(ATheme + LineEnding + ':root { --fieldpad-test: 1px; }');
    ctl.Density := ADensity;
    case AKind of
      KEdit:
        begin
          ed := TTyEdit.Create(host);
          ed.Font.PixelsPerInch := 96;
          ed.Controller := ctl;
          ed.Text := 'H';
          c := ed;
        end;
      KCombo:
        begin
          cb := TTyComboBox.Create(host);
          cb.Font.PixelsPerInch := 96;
          cb.Controller := ctl;
          cb.Items.Add('H');
          cb.ItemIndex := 0;
          c := cb;
        end;
      KComboEdit:
        begin
          ce := TTyComboEdit.Create(host);
          ce.Font.PixelsPerInch := 96;
          ce.Controller := ctl;
          ce.Text := 'H';
          c := ce;
        end;
      KTreeSelect:
        begin
          ts := TTyTreeSelect.Create(host);
          ts.Font.PixelsPerInch := 96;
          ts.Controller := ctl;
          ts.TextHint := 'H';
          c := ts;
        end;
      KSpin:
        begin
          sp := TTySpinEdit.Create(host);
          sp.Font.PixelsPerInch := 96;
          sp.Controller := ctl;
          sp.Value := 8;
          c := sp;
        end;
      KCascader:
        begin
          cas := TTyCascader.Create(host);
          cas.Font.PixelsPerInch := 96;
          cas.Controller := ctl;
          cas.Nodes.AddNode('H');
          SetLength(path, 1);
          path[0] := 0;
          cas.Path := path;
          c := cas;
        end;
    else
      begin
        dt := TTyDateTimePicker.Create(host);
        dt.Font.PixelsPerInch := 96;
        dt.Controller := ctl;
        dt.Kind := dtkDate;
        dt.Date := EncodeDate(2026, 10, 25);
        c := dt;
      end;
    end;
    host.SetBounds(0, 0, W, H);
    c.Parent := host;
    c.SetBounds(0, 0, W, H);
    TyTestSettle(host);
    shot := TBitmap.Create;
    shot.PixelFormat := pf24bit;
    shot.SetSize(W, H);
    shot.Canvas.Brush.Color := clWhite;
    shot.Canvas.FillRect(0, 0, W, H);
    TyTestPaintTree(host, shot, nil);
    b := TBGRABitmap.Create(shot);
    try
      face := b.GetPixel(2, H div 2);
      for y := H div 2 - 8 to H div 2 + 8 do
        for x := 2 to W div 2 do
        begin
          px := b.GetPixel(x, y);
          if (Abs(px.red - face.red) > 48) or (Abs(px.green - face.green) > 48) or
             (Abs(px.blue - face.blue) > 48) then
          begin
            if (Result < 0) or (x < Result) then Result := x;
            Break;
          end;
        end;
    finally
      b.Free;
    end;
  finally
    shot.Free;
    host.Free;
    ctl.Free;
  end;
end;

procedure TFieldPadTest.CheckAll(const AWhat, ATheme: string; ADensity: TTyDensity;
  ALo, AHi: Integer);
var
  k, x: Integer;
begin
  for k := KEdit to KPicker do
  begin
    x := TextLeft(k, ATheme, ADensity);
    AssertTrue(Format('%s: the %s''s text starts at x=%d, want %d..%d',
      [AWhat, KindName[k], x, ALo, AHi]), (x >= ALo) and (x <= AHi));
  end;
end;

procedure TFieldPadTest.TestEveryFieldStartsItsTextTenPxIn;
begin
  CheckAll('stock theme', '', tdClassic, 9, 11);
end;

procedure TFieldPadTest.TestTheBuiltinDefaultThemeToo;
begin
  CheckAll('built-in default', TyBuiltinThemeCss('default'), tdClassic, 9, 11);
end;

procedure TFieldPadTest.TestModernDensityMovesThemTogether;
begin
  CheckAll('modern density', '', tdModern, 12, 14);
end;

procedure TFieldPadTest.TestOneTokenReachesEveryFieldInEveryBundledTheme;
var
  names, css: array of string;
  i, k: Integer;
  m: TTyStyleModel;
  s: TTyStyleSet;
  sl: TStringList;

  function FromFile(const ARel: string): string;
  begin
    sl.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + ARel);
    Result := sl.Text;
  end;

begin
  sl := TStringList.Create;
  try
    names := ['stock', 'built-in default', 'built-in system', 'dark.tycss', 'green.tycss',
      'the theming example''s green.tycss'];
    css := ['', TyBuiltinThemeCss('default'), TyBuiltinThemeCss('system'),
      FromFile('themes' + PathDelim + 'dark.tycss'),
      FromFile('themes' + PathDelim + 'green.tycss'),
      FromFile('examples' + PathDelim + 'theming' + PathDelim + 'green.tycss')];
  finally
    sl.Free;
  end;
  for i := 0 to High(css) do
    for k := 0 to High(FieldKeys) do
    begin
      m := TTyStyleModel.Create;
      try
        m.LoadFromCss(css[i]);
        s := m.ResolveStyle(FieldKeys[k], '', []);
        AssertEquals(names[i] + ': ' + FieldKeys[k] + ' left padding is --pad-field''s', 9,
          s.Padding.Left);
        AssertEquals(names[i] + ': ' + FieldKeys[k] + ' right padding is --pad-field''s', 9,
          s.Padding.Right);
        m.LoadFromCss(css[i] + LineEnding + ':root { --pad-field: 3px 21px; }');
        s := m.ResolveStyle(FieldKeys[k], '', []);
        AssertEquals(names[i] + ': ' + FieldKeys[k] + ' follows a retuned --pad-field (left)',
          21, s.Padding.Left);
        AssertEquals(names[i] + ': ' + FieldKeys[k] + ' follows a retuned --pad-field (top)',
          3, s.Padding.Top);
      finally
        m.Free;
      end;
    end;
end;

initialization
  RegisterTest(TFieldPadTest);
end.
