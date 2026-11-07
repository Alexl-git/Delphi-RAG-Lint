unit DragLint.Plugin.UsagesQuery;

/// <summary>The pure half of Find Usages over `draglint/usages` (O-USAGESFORM): the
/// request parameters, the reply reader and the test that the running server can answer
/// for the databases a query asked about. No VCL, no ToolsAPI: a console test covers it.</summary>

interface

uses
  System.JSON
  ;

/// <summary>The parameters of a `draglint/usages` request.</summary>
/// <param name="pName">The symbol; must not be empty (the server refuses it).</param>
/// <param name="pWidth">narrow, wide or very-wide; the CLI's --width.</param>
/// <returns>A new object; the caller owns it.</returns>
function UsagesLspParams(const pName, pWidth: string): TJSONObject;

/// <summary>Takes the usages document out of a JSON-RPC reply envelope.</summary>
/// <param name="pReply">The whole envelope; nil is allowed.</param>
/// <param name="pJson">The `result` object as text, which has the shape of
/// `drag-lint usages --format json`; '' when the answer is False.</param>
/// <returns>True when the envelope carries a usages `result`. False for an error reply
/// (an engine without the method), a missing `result` or another shape: the caller then
/// asks the CLI, so a reply it cannot read never reads as "no usages".</returns>
function UsagesFromReply(pReply: TJSONValue; out pJson: string): Boolean;

/// <summary>Tells whether a server started with pServerDbs can answer a query about pDbs.</summary>
/// <param name="pDbs">The databases of the query; blank entries are skipped.</param>
/// <param name="pServerDbs">The databases the server was started with.</param>
/// <returns>True when pDbs holds at least one path and every path is among pServerDbs
/// (compared expanded, case-insensitive). False for an empty query: only the CLI can say
/// what is wrong with a query that resolved no database.</returns>
/// <remarks>A SUBSET, not an equal set: the Structure form asks about the unit's own
/// database and the server has that one plus its neighbours, so the answer may also
/// list rows from those.</remarks>
function ServerCoversDbs(const pDbs, pServerDbs: TArray<string>): Boolean;

implementation

uses
  System.SysUtils
  ;

const
  KEY_RESULT = 'result';
  KEY_ERROR  = 'error';
  { Always in the usages document; ParseUsagesGrouped tells the shape by the same key. }
  KEY_READS  = 'reads';

function UsagesLspParams(const pName, pWidth: string): TJSONObject;
begin
  Result:= TJSONObject.Create;
  Result.AddPair('name' , pName );
  Result.AddPair('width', pWidth);
end;

function UsagesFromReply(pReply: TJSONValue; out pJson: string): Boolean;
var
  Env: TJSONObject;
  Res: TJSONObject;
begin
  pJson := '';
  Result:= False;
  if pReply is not TJSONObject then Exit;
  Env:= TJSONObject(pReply);
  if Env.GetValue(KEY_ERROR) <> nil then Exit;
  if Env.GetValue(KEY_RESULT) is not TJSONObject then Exit;
  Res:= TJSONObject(Env.GetValue(KEY_RESULT));
  if Res.GetValue(KEY_READS) = nil then Exit;
  pJson := Res.ToJSON;
  Result:= True;
end;

function ServerCoversDbs(const pDbs, pServerDbs: TArray<string>): Boolean;

  function Held(const pDb: string): Boolean;
  begin
    Result:= False;
    for var S in pServerDbs do
      if (S <> '') and SameText(ExpandFileName(S), ExpandFileName(pDb)) then Exit(True);
  end;

begin
  Result:= False;
  for var D in pDbs do
  begin
    if D = '' then Continue;
    if not Held(D) then Exit(False);
    Result:= True;
  end;
end;

end.