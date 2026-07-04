unit test.dialogs.about;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Dialogs.About;
type
  { The About dialog's contract: every optional field (description / copyright / license /
    homepage) becomes a body row ONLY when non-empty, so the dialog shrinks to what it has. }
  TAboutDialogTest = class(TTestCase)
  published
    procedure TestAllFieldsPresent;
    procedure TestHidesEmptyFields;
    procedure TestMultilineDescription;
  end;
implementation

procedure TAboutDialogTest.TestAllFieldsPresent;
var d: TTyAboutForm;
begin
  d := TyBuildAboutDialog('About', 'MyApp', 'Version 1.0',
    'A great app', '(c) 2026 Me', 'MIT', 'https://example.com');
  try
    // description(1) + copyright(1) + license(1) + homepage(1)
    AssertEquals('all four optional rows present', 4, d.RowCount);
  finally d.Free; end;
end;

procedure TAboutDialogTest.TestHidesEmptyFields;
var d: TTyAboutForm;
begin
  d := TyBuildAboutDialog('About', 'MyApp', 'Version 1.0', '', '', '', '');
  try
    AssertEquals('no body rows when every optional field is empty', 0, d.RowCount);
  finally d.Free; end;
  d := TyBuildAboutDialog('', 'MyApp', '', '', '', '', 'https://x.y');
  try
    AssertEquals('only the homepage row', 1, d.RowCount);
  finally d.Free; end;
end;

procedure TAboutDialogTest.TestMultilineDescription;
var d: TTyAboutForm;
begin
  d := TyBuildAboutDialog('About', 'MyApp', '', 'line one'#10'line two', '', '', '');
  try
    AssertEquals('a 2-line description becomes 2 rows', 2, d.RowCount);
  finally d.Free; end;
end;

initialization
  RegisterTest(TAboutDialogTest);
end.
