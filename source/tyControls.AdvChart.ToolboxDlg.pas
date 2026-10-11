unit tyControls.AdvChart.ToolboxDlg;
{$mode objfpc}{$H+}
{ The toolbox's two dialogs, in the library's own dialog family [Batch 125,
  C16].

  dataView: upstream lays a panel over the chart -- a heading, a textarea
  with the table text and two buttons, Refresh (left out when `readOnly`)
  and Close. Here it is a TTyDialog with the same parts: the heading is the
  dialog's caption, the text a monospaced TTyMemo, Refresh the default
  button (mrOK) and Close the cancel one. The colours upstream reads off the
  feature (backgroundColor, textColor, textareaColor, buttonColor ...) are
  the skin's here, as every dialog's are.

  saveAsImage: upstream makes the browser download the file; here the
  library's save dialog asks where, seeded with the name upstream would
  download as.

  TyBuildDataViewDialog makes the dialog without showing it, so a test can
  look at it; the Show calls are the thin layer the chart calls through its
  virtual seams (TTyAdvanceChart.ToolboxShowDataView /
  ToolboxAskFileName). }
interface
uses
  Classes, SysUtils, Controls, Forms, StdCtrls,
  tyControls.Dialogs, tyControls.Memo;

{ The data view, not shown: the memo holds AText. }
function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out AMemo: TTyMemo): TTyDialog;
{ The data view, modal: True when Refresh closed it, with the memo's text in
  AText. }
function TyShowDataViewDialog(const ATitle: string; var AText: string;
  AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean;
{ The save dialog for saveAsImage: AFileName the suggested name in, the
  chosen path out. }
function TyAskImageFileName(var AFileName: string; const AType: string): Boolean;

implementation

uses tyControls.StrConsts, tyControls.Dialogs.FileDialog;

const
  { the text area, logical px }
  cDvWidth = 560;
  cDvHeight = 320;

function TyBuildDataViewDialog(const ATitle, AText: string; AReadOnly: Boolean;
  const ACloseCaption, ARefreshCaption: string; out AMemo: TTyMemo): TTyDialog;
var
  pad, w, h: Integer;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ATitle;
  pad := Result.Px(TyDlgPad);
  w := Result.Px(cDvWidth);
  h := Result.Px(cDvHeight);
  AMemo := TTyMemo.Create(Result);
  AMemo.Parent := Result;
  AMemo.ScrollBars := ssAutoBoth;
  AMemo.WordWrap := False;
  AMemo.Font.Name := 'Courier New';
  AMemo.Text := AText;
  AMemo.ReadOnly := AReadOnly;
  AMemo.SetBounds(Result.ContentRect.Left + pad, Result.ContentRect.Top + pad, w, h);
  { upstream floats Refresh, then Close, to the right: Refresh is the
    rightmost }
  if not AReadOnly then Result.AddButton(ARefreshCaption, mrOK, True, False);
  Result.AddButton(ACloseCaption, mrCancel, AReadOnly, True);
  Result.AutoSizeToContent(w + 2 * pad, h + 2 * pad);
end;

function TyShowDataViewDialog(const ATitle: string; var AText: string;
  AReadOnly: Boolean; const ACloseCaption, ARefreshCaption: string): Boolean;
var
  d: TTyDialog;
  m: TTyMemo;
  i: Integer;
begin
  d := TyBuildDataViewDialog(ATitle, AText, AReadOnly, ACloseCaption, ARefreshCaption, m);
  try
    Result := (d.ShowModal = mrOK) and not AReadOnly;
    { the memo's lines, joined by bare newlines as a textarea's value is --
      no break after the last }
    if Result then
    begin
      AText := '';
      for i := 0 to m.Lines.Count - 1 do
      begin
        if i > 0 then AText := AText + #10;
        AText := AText + m.Lines[i];
      end;
    end;
  finally
    d.Free;
  end;
end;

function TyAskImageFileName(var AFileName: string; const AType: string): Boolean;
var ext: string;
begin
  if AType = 'jpeg' then ext := 'jpeg' else ext := AType;
  Result := TySaveDialog(AFileName, rsTyChartToolboxImageFilter, ext);
end;

end.
