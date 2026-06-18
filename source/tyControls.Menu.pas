unit tyControls.Menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, LCLProc, Menus,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

type
  TTyMenuRowKind = (mrkItem, mrkSeparator);
  TTyMenuRow = record
    Kind: TTyMenuRowKind;
    Item: TMenuItem;        // source item (for activation / submenu)
    Caption: string;
    ShortcutText: string;   // ShortCutToText(Item.ShortCut)
    Enabled: Boolean;
    Checked: Boolean;
    RadioItem: Boolean;
    HasSubmenu: Boolean;
    DefaultItem: Boolean;   // render bold
  end;
  TTyMenuRowArray = array of TTyMenuRow;

{ Flatten a root TMenuItem's visible children into render rows. Caption '-' => separator. }
function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;

implementation

function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;
var i, n: Integer; mi: TMenuItem;
begin
  SetLength(Result, 0);
  if ARoot = nil then Exit;
  n := 0;
  SetLength(Result, ARoot.Count);
  for i := 0 to ARoot.Count - 1 do
  begin
    mi := ARoot.Items[i];
    if not mi.Visible then Continue;
    Result[n] := Default(TTyMenuRow);
    Result[n].Item := mi;
    if mi.IsLine then
      Result[n].Kind := mrkSeparator
    else
    begin
      Result[n].Kind := mrkItem;
      Result[n].Caption := mi.Caption;
      Result[n].ShortcutText := ShortCutToText(mi.ShortCut);
      Result[n].Enabled := mi.Enabled;
      Result[n].Checked := mi.Checked;
      Result[n].RadioItem := mi.RadioItem;
      Result[n].HasSubmenu := mi.Count > 0;
      Result[n].DefaultItem := mi.Default;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;
end.
