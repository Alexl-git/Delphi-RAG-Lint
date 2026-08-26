unit uPhantomCall;

{ Fixture for run_doc_phantom_call.ps1.

  TGate's CLASS-LEVEL <remarks> contains a usage sketch naming a sibling method
  (Gate.Beta). No method here calls Beta except CallsBeta, which really does.
  If prose ever reaches the call extractor again, Alpha or Gamma will sprout a
  "Calls: Beta" fact and the guard fails. }

interface

type
  /// <summary>Gate whose class remarks contain a usage sketch.</summary>
  /// <remarks>
  /// Typical use:
  ///     -> run the stop, then: if Gate.Beta(SomeFlag) then lock every tab
  /// </remarks>
  TGate = class
    private
      FPending: Boolean;
    public
      /// <summary>Calls nothing. Declared FIRST, so it is the nearest
      /// declaration below the prose.</summary>
      function Alpha(AFlag: Boolean): Boolean;
      /// <summary>Also calls nothing.</summary>
      function Gamma(AFlag: Boolean): Boolean;
      /// <summary>The method named in the prose above.</summary>
      function Beta(AFlag: Boolean): Boolean;
      /// <summary>POSITIVE CONTROL -- really does call Beta.</summary>
      function CallsBeta(AFlag: Boolean): Boolean;
  end;

implementation

function TGate.Alpha(AFlag: Boolean): Boolean;
begin
  Result:= not AFlag;
  FPending:= not Result;
end;

function TGate.Gamma(AFlag: Boolean): Boolean;
begin
  Result:= AFlag;
end;

function TGate.Beta(AFlag: Boolean): Boolean;
begin
  Result:= AFlag and FPending;
end;

function TGate.CallsBeta(AFlag: Boolean): Boolean;
begin
  Result:= Beta(AFlag);
end;

end.
