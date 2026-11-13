unit MiB;

// Plan fixture (lane CYC3 finisher): declares the class MiA's initialization registers. TMiJob's own use of
// MiA takes the address of a routine, so the class cannot move and the edge MiB -> MiA is never an inversion.

interface

uses
  System.Classes;

type
  /// <summary>The class MiA passes as a value.</summary>
  TMiJob = class(TPersistent)
  public
    /// <summary>Takes the address of MiAValue.</summary>
    procedure Kick;
  end;

/// <summary>Takes nothing; its address is taken by MiC.</summary>
procedure MiBTick;

implementation

uses
  MiA;

var
  GValue: function: Integer;

procedure TMiJob.Kick;
begin
  GValue:= @MiAValue;
end;

procedure MiBTick;
begin
  Writeln('[b] tick');
end;

initialization
  Writeln('init MiB');

end.
