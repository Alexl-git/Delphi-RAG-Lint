unit uMaxLen;

{ schema-maxlen-drift fixture (lane FR-LINT): <TABLE>_<FIELD>_MAXLEN constants checked against the
  field repository's char lengths (repo.txt). }

interface

const
  MSCLIST_DIMNAME_MAXLEN = 35; { DIMNAME holds 35 -> silent (positive control) }
  MSCLIST_DIMABBR_MAXLEN = 35; { DIMABBR holds 10 via domain D_ABBR -> FIRES }
  MSCLIST_NOPE_MAXLEN = 5; { no such column -> silent }
  orders_note_maxlen = 30; { lower-case name; NOTE holds 20 -> FIRES }
  CFG_ITEM_CODE_MAXLEN = 12; { table CFG$ITEM written CFG_ITEM; CODE holds 8 -> FIRES }
  CFG_ITEM_CODE_WIDTH = 99; { not a _MAXLEN name -> silent }

implementation

end.
