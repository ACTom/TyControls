unit tyControls.TreeView.Columns;
{$mode objfpc}{$H+}
{ DEPRECATED compatibility shim.

  The column model used to live here, back when TTyTreeView was its only consumer. It now
  lives in tyControls.Columns, because TTyListView's report mode shares it — and a control
  that is not a tree should not publish a `Header: TTyTreeHeader`.

  This unit exists so code written against v2.2 (`uses tyControls.TreeView.Columns`) keeps
  compiling. It re-exports the types under their old names and the enum values under their
  own names (a type alias does not carry an enumeration's values into scope).

  New code should `uses tyControls.Columns` and the TTyColumn / TTyColumns / TTyHeader
  names. This shim will be removed in a future major version. }
interface

uses
  tyControls.Columns;

const
  NoColumn = tyControls.Columns.NoColumn;

type
  TTyTreeColumnOption  = tyControls.Columns.TTyColumnOption;
  TTyTreeColumnOptions = tyControls.Columns.TTyColumnOptions;
  TTyTreeColumn        = tyControls.Columns.TTyColumn;
  TTyTreeColumns       = tyControls.Columns.TTyColumns;
  TTyTreeHeaderOption  = tyControls.Columns.TTyHeaderOption;
  TTyTreeHeaderOptions = tyControls.Columns.TTyHeaderOptions;
  TTyTreeHeader        = tyControls.Columns.TTyHeader;
  TTySortDirection     = tyControls.Columns.TTySortDirection;

const
  { Enum values, re-exported. `TFoo = Other.TFoo` aliases the TYPE only; without these a
    client of this unit could not write `[coVisible]` or `sdAscending`. }
  coVisible             = tyControls.Columns.coVisible;
  coResizable           = tyControls.Columns.coResizable;
  coAllowClick          = tyControls.Columns.coAllowClick;
  coDraggable           = tyControls.Columns.coDraggable;
  coAutoSpring          = tyControls.Columns.coAutoSpring;

  hoVisible             = tyControls.Columns.hoVisible;
  hoColumnResize        = tyControls.Columns.hoColumnResize;
  hoShowSortGlyphs      = tyControls.Columns.hoShowSortGlyphs;
  hoHeaderClickAutoSort = tyControls.Columns.hoHeaderClickAutoSort;
  hoDrag                = tyControls.Columns.hoDrag;
  hoAutoResize          = tyControls.Columns.hoAutoResize;
  hoHotTrack            = tyControls.Columns.hoHotTrack;

  sdAscending           = tyControls.Columns.sdAscending;
  sdDescending          = tyControls.Columns.sdDescending;

implementation

end.
