unit test.skins;
{ Every themes/*.tycss (curated palettes + structural skins) must LOAD and RESOLVE without
  raising — the guard for the whole themes/ folder. Dual-mode files (the curated palettes,
  which @import the dual-mode base) are seeded to their default mode first so @mode-only vars
  are defined; single-mode structural skins resolve as-is. Any bad file is named in the failure. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TSkinsTest = class(TTestCase)
  published
    procedure TestAllThemeFilesLoadAndResolve;
  end;

implementation

procedure TSkinsTest.TestAllThemeFilesLoadAndResolve;
var
  base, failed: string;
  n: Integer;

  procedure ScanDir(const ADir: string);
  var sr: TSearchRec; m: TTyStyleModel;
  begin
    if not DirectoryExists(ADir) then Exit;
    if FindFirst(ADir + '*.tycss', faAnyFile, sr) = 0 then
      try
        repeat
          if (sr.Attr and faDirectory) = 0 then
          begin
            Inc(n);
            m := TTyStyleModel.Create;
            try
              try
                m.LoadFromFile(ADir + sr.Name);
                if m.DefaultModeName <> '' then
                  m.SetMode(m.DefaultModeName);   // dual-mode files: seed so @mode-only vars resolve
                m.ResolveStyle('TyButton', '', []);
                m.ResolveStyle('TyButton', 'primary', []);
                m.ResolveStyle('TyEdit', '', []);
                m.ResolveStyle('TyTitleBar', '', []);
              except
                on E: Exception do
                  failed := failed + sr.Name + ' <' + E.Message + '>; ';
              end;
            finally
              m.Free;
            end;
          end;
        until FindNext(sr) <> 0;
      finally
        FindClose(sr);
      end;
  end;

begin
  base := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim;
  AssertTrue('themes/ dir exists', DirectoryExists(base));
  failed := '';
  n := 0;
  ScanDir(base);                              // the structural skins
  ScanDir(base + 'palettes' + PathDelim);     // the archived curated palettes
  AssertTrue('found some theme files', n > 0);
  AssertEquals('all theme files load + resolve', '', failed);
end;

initialization
  RegisterTest(TSkinsTest);
end.
