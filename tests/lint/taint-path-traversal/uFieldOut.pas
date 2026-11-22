unit uFieldOut;

{ SLZ-TAINTFP (1.52.3) fixture: taint written into ONE field of a var parameter.
  Annotate / AnnotatePath copy console input into one field of every element; the
  consumers below read either that field or another one. Shape of the 1.52.2
  self-lint false positives (RefuseNamedUnits writes dcc text into TGpaUnit.Error;
  RunGate later deletes / backs up through TGpaUnit.PasPath only). }

interface

type
  TItem = record
    Path: string;
    Note: string;
  end;
  TItems = TArray<TItem>;

procedure Run;

implementation

uses
  System.SysUtils;

procedure Annotate(var pItems: TItems; const pText: string);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    pItems[I].Note := pText;
end;

procedure AnnotatePath(var pItems: TItems; const pText: string);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    pItems[I].Path := pText;
end;

procedure KillOne(const pFile: string);
begin
  DeleteFile(pFile);
end;

procedure DeleteByPath(const pItems: TItems);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    DeleteFile(pItems[I].Path);
end;

procedure DeleteByPathDeep(const pItems: TItems);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    KillOne(pItems[I].Path);
end;

procedure DeleteByNote(const pItems: TItems);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    DeleteFile(pItems[I].Note);
end;

function NoteOf(const pItem: TItem): string;
begin
  Result := pItem.Note;
end;

procedure DeleteThroughCall(const pItems: TItems);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    DeleteFile(NoteOf(pItems[I]));
end;

procedure DeleteWritten(const pItems: TItems);
var
  I: Integer;
begin
  for I := 0 to High(pItems) do
    DeleteFile(pItems[I].Path);
end;

procedure Run;
var
  A, B: TItems;
  S: string;
begin
  SetLength(A, 1);
  A[0].Path := 'C:\Temp\a.txt';
  ReadLn(S);
  Annotate(A, S);
  DeleteByPath(A);
  DeleteByPathDeep(A);
  DeleteByNote(A);
  DeleteThroughCall(A);
  SetLength(B, 1);
  AnnotatePath(B, S);
  DeleteWritten(B);
end;

end.
