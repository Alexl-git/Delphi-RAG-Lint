unit uBounds;

{ schema-maxlen-drift (literal) and schema-length-bound (Copy) fixture (lane FR-LINT). The ORM
  classes are linked by link-orm against schema.sql (TMSCLIST.FDIMABBR -> MSCLIST.DIMABBR). }

interface

uses
  uMaxLen;

type
  TMSCLIST = class
  private
    FDIMNAME: string;
    FDIMABBR: string;
  public
    property DIMNAME: string read FDIMNAME write FDIMNAME;
    property DIMABBR: string read FDIMABBR write FDIMABBR;
  end;

  TORDERS = class
  private
    FNOTE: string;
    procedure SetNoteTrim(const pValue: string);
  public
    property NOTE: string read FNOTE write FNOTE;
    property NOTETRIM: string read FNOTE write SetNoteTrim;
  end;

procedure FillList(pList: TMSCLIST; const pText: string);
procedure FillOrder(pOrder: TORDERS);

implementation

procedure TORDERS.SetNoteTrim(const pValue: string);
begin
  FNOTE := Copy(pValue, 1, 20); { 20 -> silent }
end;

procedure FillList(pList: TMSCLIST; const pText: string);
var
  tDIMABBR: string;
begin
  pList.DIMABBR := Copy(pText, 1, MSCLIST_DIMNAME_MAXLEN); { 35 > 10 -> FIRES schema-length-bound }
  pList.DIMABBR := Copy(pText, 1, 10); { 10 -> silent }
  pList.DIMNAME := Copy(pText, 1, MSCLIST_DIMNAME_MAXLEN); { 35 -> silent }
  tDIMABBR := Copy(pText, 1, 35); { local named after the field: not resolved in 1.53 (FR-6) -> silent }
  pList.DIMNAME := tDIMABBR;
end;

procedure FillOrder(pOrder: TORDERS);
begin
  pOrder.NOTE := '123456789012345678901'; { 21 > 20 -> FIRES schema-maxlen-drift }
  pOrder.NOTE := '12345678901234567890'; { 20 -> silent }
end;

end.
