unit uTtStubHomonym;

{ A second library class named THomonym that is NOT a control: the name stands for two
  classes, so the closure is their intersection and the rule stays silent. }

interface

type
  THomonym = class(TObject)
  public
    Caption: string;
  end;

implementation

end.
