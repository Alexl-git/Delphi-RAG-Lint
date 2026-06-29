unit vbase;

// Base unit for the cross-unit virtual-method-in-constructor test. VVirt is a
// virtual method declared here; a descendant's constructor (in vchild) calls it.

interface

type
  TVBase = class
    procedure VVirt; virtual;
    procedure VPlain;
  end;

implementation

procedure TVBase.VVirt;
begin
end;

procedure TVBase.VPlain;
begin
end;

end.
