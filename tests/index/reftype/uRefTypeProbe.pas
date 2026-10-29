unit uRefTypeProbe;

{ Lane REFTYPE fixture: every shape where a type is named ONLY inside a
  procedural / anonymous-method / open-array signature in the INTERFACE
  section. Each line carries an M- marker comment; the runner asserts a
  type_use ref for the named type on that marker's line. All the named types
  live in uRefTypeDefs, so uses-audit must keep that unit in the interface. }

interface

uses
  System.SysUtils,
  uRefTypeDefs;

type
  TRefFunc = reference to function(const pA: TRtParamA): TRtResA; { M-REFFUNC }
  TRefProc = reference to procedure(pB: TRtParamB); { M-REFPROC }
  TMethFunc = function(pC: TRtParamC): TRtResC of object; { M-METHFUNC }
  TPlainProc = procedure(pD: TRtParamD); { M-PLAINPROC }
  TGenRes = reference to function: TFunc<TRtGenE>; { M-GENRES }
  TGenParam = reference to procedure(const pF: TProc<TRtGenF>); { M-GENPARAM }
  TOpenArr = reference to procedure(const pG: array of TRtOpenG); { M-OPENARR }
  TDefault = procedure(pH: TRtDefH = nil); { M-DEFAULT }
  TArrRes = reference to function: TArray<TRtArrI>; { M-ARRRES }
  TSetOf = set of TRtSetO; { M-SETOF }
  TArrOf = array of TRtArrP; { M-ARROF }
  TIdxArr = array[TRtIdxQ] of TRtElemQ; { M-IDXARR }
  TClassOf = class of TRtClsR; { M-CLASSOF }
  TNestedProc = reference to procedure(const pS: TRtGenS<TRtArgS>); { M-NESTGEN }

  TRtHolder = class
  private
    FHook: procedure(pJ: TRtFieldJ) of object; { M-FIELD }
  public
    procedure Run(const pK: array of TRtOpenK); { M-METHOPEN }
    function Make(pL: TRtDefL = nil): TRtResL; { M-METHDEF }
  end;

const
  CHook: procedure(pM: TRtConstM) = nil; { M-CONST }

var
  GHook: function(pN: TRtVarN): TRtVarResN; { M-VAR }

implementation

procedure TRtHolder.Run(const pK: array of TRtOpenK);
begin
  if Length(pK) = 0 then Exit;
end;

function TRtHolder.Make(pL: TRtDefL): TRtResL;
begin
  Result:= TRtResL(pL);
end;

end.
