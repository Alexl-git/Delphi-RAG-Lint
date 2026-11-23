unit Pipes.Protocol;

{ Stub of the ORM3 unit of the same name: only what the generated _CLIENT units reference. }

interface

type
  TCommandID = (cmdLoad, cmdSave, cmdDelete, cmdNextID, rspOK, rspData, rspNotFound, rspError);

  TPipeMessageHeader = record
    CommandID: Byte;
  end;

function CommandIDToStr(ACmd: TCommandID): string;

implementation

function CommandIDToStr(ACmd: TCommandID): string;
begin
  Result := Char(Ord('0') + Ord(ACmd));
end;

end.
