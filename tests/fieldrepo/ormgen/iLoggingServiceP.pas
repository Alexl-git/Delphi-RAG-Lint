unit iLoggingServiceP;

{ Stub of the ORM3 unit of the same name: only what the generated units reference. }

interface

uses
  System.SysUtils;

type
  TMessageType = (mtInfo, mtWarning, mtError);

  TLogContext = record
    ErrorCode: Integer;
    class function ForDB(const ATable, ASql: string): TLogContext; static;
  end;

  IABZLoggingSys = interface
    ['{A1B2C3D4-E5F6-7890-ABCD-EF1234564321}']
    procedure Warning(const AMsg: string; const AContext: TLogContext);
    procedure Trace(const AMsg: string; const AContext: TLogContext);
    procedure LogFireDACError(E: Exception; const AContext: TLogContext);
    procedure LogException(E: Exception; const AMsg: string; const AContext: TLogContext);
    procedure LogTransactionCommit(const AContext: TLogContext);
    procedure LogTransactionRollback(const AMsg: string; const AContext: TLogContext);
    procedure LogMessage(AType: TMessageType; const AMsg: string; ALevel: Integer);
  end;

implementation

class function TLogContext.ForDB(const ATable, ASql: string): TLogContext;
begin
  Result.ErrorCode := 0;
end;

end.
