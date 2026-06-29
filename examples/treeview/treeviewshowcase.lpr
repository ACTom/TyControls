program treeviewshowcase;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms,
  showcasemain;

{$R *.res}

begin
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TShowcaseForm, ShowcaseForm);
  Application.Run;
end.
