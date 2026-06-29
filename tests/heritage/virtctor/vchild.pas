unit vchild;

// TVChild's constructor calls VVirt, an INHERITED virtual declared in vbase.
// Within-file analysis cannot see it (VVirt is not declared in TVChild); the
// store-backed cross-unit check must catch it.

interface

uses
  vbase;

type
  TVChild = class(TVBase)
  public
    constructor Create;
  end;

implementation

constructor TVChild.Create;
begin
  inherited Create;
  VVirt;     // line 23: inherited virtual called from ctor -> must fire (store path)
  VPlain;    // line 24: not virtual -> must NOT fire
end;

end.
