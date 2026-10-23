unit MT.Catalog;

{ menu-tree fixture: the BuildReportsMenu shape -- a const array of records,
  a case-of-literals group function and a builder that receives its item and
  header factories as procedural parameters. Compiled, never run. }

interface

uses
  Vcl.Menus;

type
  TCatalogKind = (ckBasic, ckAdvanced);

  TCatalogEntry = record
    Id     : string;
    Caption: string;
    Kind   : TCatalogKind;
  end;

  TCatalogAddItem   = reference to function(pParent: TMenuItem; const pCaption: string): TMenuItem;
  TCatalogAddHeader = reference to procedure(pParent: TMenuItem; const pCaption: string);

const
  CATALOG: array[0..2] of TCatalogEntry = (
    (Id: 'basic'   ; Caption: 'Basic Report...'   ; Kind: ckBasic   ),
    (Id: 'advanced'; Caption: 'Advanced Report...'; Kind: ckAdvanced),
    (Id: 'summary' ; Caption: 'Summary Report'    ; Kind: ckBasic   ));

function CatalogGroupCaption(pKind: TCatalogKind): string;

procedure BuildCatalogMenu(pParent: TMenuItem; const pAddItem: TCatalogAddItem;
  const pAddHeader: TCatalogAddHeader);

implementation

function CatalogGroupCaption(pKind: TCatalogKind): string;
begin
  case pKind of
    ckBasic: Result:= 'Basic Group';
  else
    Result:= 'Advanced Group';
  end;
end;

procedure BuildCatalogMenu(pParent: TMenuItem; const pAddItem: TCatalogAddItem;
  const pAddHeader: TCatalogAddHeader);
begin
  for var Kind: TCatalogKind:= Low(TCatalogKind) to High(TCatalogKind) do
  begin
    pAddHeader(pParent, CatalogGroupCaption(Kind));
    for var I: Integer:= Low(CATALOG) to High(CATALOG) do
      if CATALOG[I].Kind = Kind then pAddItem(pParent, CATALOG[I].Caption).Tag:= I;
  end;
end;

end.
