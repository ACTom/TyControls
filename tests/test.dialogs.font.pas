unit test.dialogs.font;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Graphics, Controls, fpcunit, testregistry, tyControls.Dialogs.Font;
type
  TFontMapTest = class(TTestCase)
  published
    procedure TestStyleRoundTrip;
  end;
  TFontDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsChecksAndList;
  end;
implementation
procedure TFontMapTest.TestStyleRoundTrip;
var i: Integer; st, st2: TFontStyles; ch: TTyFontChecks;
begin
  for i := 0 to 15 do
  begin
    st := [];
    if (i and 1)<>0 then Include(st, fsBold);
    if (i and 2)<>0 then Include(st, fsItalic);
    if (i and 4)<>0 then Include(st, fsUnderline);
    if (i and 8)<>0 then Include(st, fsStrikeOut);
    ch := TyFontStyleToChecks(st);
    st2 := TyChecksToFontStyle(ch);
    AssertTrue('rt '+IntToStr(i), st = st2);
  end;
end;
procedure TFontDialogTest.TestBuildSeedsChecksAndList;
var f: TFont; d: TTyFontForm; fams: TStringList;
begin
  f := TFont.Create;
  fams := TStringList.Create;
  try
    f.Name := 'Courier New'; f.Size := 14; f.Style := [fsBold, fsItalic];
    fams.Add('Arial'); fams.Add('Courier New'); fams.Add('Segoe UI');
    d := TyBuildFontDialog('Font', f, fams);
    try
      AssertEquals('size seeded', 14, d.SizeValue);
      AssertTrue('bold seeded', d.BoldChecked);
      AssertTrue('italic seeded', d.ItalicChecked);
      AssertFalse('underline', d.UnderlineChecked);
      AssertEquals('family count', 3, d.FamilyCount);
      AssertEquals('family selected', 'Courier New', d.SelectedFamily);
    finally d.Free; end;
  finally f.Free; fams.Free; end;
end;

initialization
  RegisterTest(TFontMapTest);
  RegisterTest(TFontDialogTest);
end.
