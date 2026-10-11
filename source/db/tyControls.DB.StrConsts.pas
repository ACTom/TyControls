unit tyControls.DB.StrConsts;

{$mode objfpc}{$H+}

interface

{ The resourcestrings of the tycontrols_db package. English is the msgid; translations live in
  languages/tycontrols.db.strconsts.<lang>.po, which an application loads beside the main
  package's catalogue:

    TranslateUnitResourceStringsEx('', LangDir, 'tycontrols.db', 'tyControls.DB.StrConsts'); }
resourcestring
  // --- Navigator: button hints ---
  rsTyDBNavFirst   = 'First record';
  rsTyDBNavPrior   = 'Previous record';
  rsTyDBNavNext    = 'Next record';
  rsTyDBNavLast    = 'Last record';
  rsTyDBNavInsert  = 'Insert record';
  rsTyDBNavDelete  = 'Delete record';
  rsTyDBNavEdit    = 'Edit record';
  rsTyDBNavPost    = 'Save changes';
  rsTyDBNavCancel  = 'Cancel changes';
  rsTyDBNavRefresh = 'Refresh data';
  // --- Navigator: asked before the Delete button deletes ---
  rsTyDBNavConfirmDelete = 'Delete this record?';

implementation

end.
