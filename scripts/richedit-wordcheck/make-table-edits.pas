program make_table_edits;
{ A Word-written table changed through the control's table doors and saved, for Word to
  open: does Word see each change? One file per change, so a change Word does not see is
  known by its name. No window is shown. }
{$mode objfpc}{$H+}

uses
  Interfaces, Forms, Classes, SysUtils, Graphics, Controls,
  tyControls.Controller, tyControls.RichEdit.Text, tyControls.RichEdit.Model,
  tyControls.RichEdit.Commands, tyControls.RichEdit.Attrs, tyControls.RichEdit.TableProps,
  tyControls.RichEdit.RowFormat,
  tyControls.RichEdit;

var
  OutDir, Fixture: string;
  Ctl: TTyStyleController;
  Log: TStringList;

function NewRich: TTyRichEdit;
begin
  Result := TTyRichEdit.Create(nil);
  Result.Controller := Ctl;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 800, 600);
end;

procedure CaretIn(ARich: TTyRichEdit; const S: string);
begin
  ARich.SelStart := 0;
  ARich.SelLength := 0;
  if not ARich.FindNext(S, []) then
    raise Exception.Create('text not found: ' + S);
  ARich.SelStart := ARich.SelStart + 1;
  ARich.SelLength := 0;
end;

type
  TChange = procedure(ARich: TTyRichEdit);

procedure Run(const AName: string; AChange: TChange);
var
  R: TTyRichEdit;
begin
  R := NewRich;
  try
    try
      R.LoadFromFile(Fixture);
      AChange(R);
      R.SaveToFile(OutDir + AName + '.rtf', rfRtf);
      Log.Add('wrote ' + AName);
    except
      on E: Exception do
        Log.Add('FAILED ' + AName + ': ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    R.Free;
  end;
end;

procedure Must(AOk: Boolean; const AWhat: string);
begin
  if not AOk then
    raise Exception.Create('refused: ' + AWhat);
end;

procedure ChNothing(ARich: TTyRichEdit);
begin
end;

procedure ChShading(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第1行第2列');
  Must(ARich.SetCellShading(TColor($00FF00)), 'SetCellShading');      // green
end;

procedure ChWidth(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第1行第2列');
  Must(ARich.SetColumnWidth(3000), 'SetColumnWidth');                 // 150 pt
end;

procedure ChRowHeight(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第1行第2列');
  Must(ARich.SetRowHeight(900, True), 'SetRowHeight');                // exactly 45 pt
end;

procedure ChPadding(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第1行第2列');
  Must(ARich.SetCellPadding(300, 100, 200, 60), 'SetCellPadding');    // 15 / 5 / 10 / 3 pt
end;

procedure ChVAlign(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第2行第3列');
  Must(ARich.SetCellVAlign(rcvBottom), 'SetCellVAlign');
end;

procedure ChBorders(ARich: TTyRichEdit);
var
  b: TTyRichBorder;
begin
  CaretIn(ARich, '第2行第2列');
  b := Default(TTyRichBorder);
  b.Style := rbsSingle;
  b.WidthTwips := 45;                                                  // 2 1/4 pt
  b.Color := TColor($FF00FF);                                          // magenta
  Must(ARich.SetCellBorders(rbpAll, b), 'SetCellBorders');
end;

procedure ChAlign(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第1行第2列');
  Must(ARich.SetTableAlign(rraRight), 'SetTableAlign');
end;

procedure ChInsertRow(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第2行第2列');
  Must(ARich.InsertRow(True), 'InsertRow');
end;

procedure ChInsertColumn(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第2行第2列');
  Must(ARich.InsertColumn(True), 'InsertColumn');
end;

procedure ChDeleteColumn(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第2行第2列');
  Must(ARich.DeleteColumn, 'DeleteColumn');
end;

procedure ChTyped(ARich: TTyRichEdit);
begin
  CaretIn(ARich, '第2行第2列');
  ARich.SelText := 'X';
end;

begin
  Application.Initialize;
  Fixture := ParamStr(1);
  OutDir := ParamStr(2);
  Log := TStringList.Create;
  Ctl := TTyStyleController.Create(nil);
  try
    Run('t0-nothing', @ChNothing);
    Run('t1-shading', @ChShading);
    Run('t2-width', @ChWidth);
    Run('t3-rowheight', @ChRowHeight);
    Run('t4-padding', @ChPadding);
    Run('t5-valign', @ChVAlign);
    Run('t6-borders', @ChBorders);
    Run('t7-align', @ChAlign);
    Run('t8-insertrow', @ChInsertRow);
    Run('t9-insertcolumn', @ChInsertColumn);
    Run('t10-deletecolumn', @ChDeleteColumn);
    Run('t11-typed', @ChTyped);
    Log.Add('ALL DONE');
  finally
    Log.SaveToFile(OutDir + 'make-table-edits.log');
    Ctl.Free;
  end;
end.
