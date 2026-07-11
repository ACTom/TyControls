unit test.previewbox;

{$mode objfpc}{$H+}

interface

{ Headless test for the PURE classifier only.

  TTyPreviewBox is a windowed control (TTyCustomControl) and cannot be
  instantiated under the console runner (no win32 handle), so the ONLY
  thing exercised here is the pure function:

    function TyPreviewClassify(const AFileName: string): TTyPreviewKind;
    TTyPreviewKind = (pkImage, pkText, pkOther);

  Expectations are derived from the plan
  (docs/superpowers/plans/2026-07-11-phase7-previewdialogs.md, lines 54-61),
  NOT from the implementation. }

uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.PreviewBox;

type
  TPreviewClassifyTest = class(TTestCase)
  private
    procedure AssertKind(const AMsg: string; AExpected: TTyPreviewKind;
      const AFileName: string);
  published
    procedure TestImageExtensionsAreImage;
    procedure TestTextExtensionsAreText;
    procedure TestCaseInsensitive;
    procedure TestOtherIsOther;
    procedure TestFullPathClassifiedByExtension;
  end;

implementation

const
  { Plan line 59: pkImage <- .png .jpg .jpeg .bmp .gif .ico .tif .tiff }
  IMAGE_EXTS: array[0..7] of string =
    ('.png', '.jpg', '.jpeg', '.bmp', '.gif', '.ico', '.tif', '.tiff');

  { Plan line 60: pkText <- .txt .md .json .log .ini .xml .csv .yml .yaml
    .html .htm .js .css .pas .lpr .inc .pp .lfm .sh .bat }
  TEXT_EXTS: array[0..19] of string =
    ('.txt', '.md', '.json', '.log', '.ini', '.xml', '.csv', '.yml', '.yaml',
     '.html', '.htm', '.js', '.css', '.pas', '.lpr', '.inc', '.pp', '.lfm',
     '.sh', '.bat');

function KindName(AKind: TTyPreviewKind): string;
begin
  case AKind of
    pkImage: Result := 'pkImage';
    pkText:  Result := 'pkText';
  else
    Result := 'pkOther';
  end;
end;

procedure TPreviewClassifyTest.AssertKind(const AMsg: string;
  AExpected: TTyPreviewKind; const AFileName: string);
var
  actual: TTyPreviewKind;
begin
  actual := TyPreviewClassify(AFileName);
  AssertTrue(Format('%s: "%s" expected %s got %s',
    [AMsg, AFileName, KindName(AExpected), KindName(actual)]),
    actual = AExpected);
end;

procedure TPreviewClassifyTest.TestImageExtensionsAreImage;
var
  i: Integer;
begin
  for i := 0 to High(IMAGE_EXTS) do
    AssertKind('image ext', pkImage, 'photo' + IMAGE_EXTS[i]);
end;

procedure TPreviewClassifyTest.TestTextExtensionsAreText;
var
  i: Integer;
begin
  for i := 0 to High(TEXT_EXTS) do
    AssertKind('text ext', pkText, 'notes' + TEXT_EXTS[i]);
end;

procedure TPreviewClassifyTest.TestCaseInsensitive;
begin
  AssertKind('upper image', pkImage, 'PHOTO.PNG');
  AssertKind('upper text', pkText, 'READ.MD');
  AssertKind('mixed image', pkImage, 'Holiday.JpG');
  AssertKind('mixed text', pkText, 'Config.Xml');
end;

procedure TPreviewClassifyTest.TestOtherIsOther;
begin
  AssertKind('exe', pkOther, 'setup.exe');
  AssertKind('zip', pkOther, 'archive.zip');
  AssertKind('no extension', pkOther, 'README');
  AssertKind('empty string', pkOther, '');
  AssertKind('bare dotfile', pkOther, '.gitignore');
end;

procedure TPreviewClassifyTest.TestFullPathClassifiedByExtension;
begin
  AssertKind('windows path image', pkImage, 'C:\photos\holiday.jpg');
  AssertKind('windows path text', pkText, 'C:\src\unit1.pas');
  AssertKind('posix path image', pkImage, '/home/user/pics/cat.png');
  AssertKind('path other', pkOther, 'C:\downloads\bundle.zip');
end;

initialization
  RegisterTest(TPreviewClassifyTest);
end.
