program demo;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms,
  mainform, chromeform;
begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TDemoMainForm, DemoMainForm);
  Application.CreateForm(TChromeForm, ChromeFormWnd);
  Application.Run;
end.
