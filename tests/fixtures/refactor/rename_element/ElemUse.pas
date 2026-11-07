unit ElemUse;

interface

procedure RunAll;

implementation

uses
  System.SysUtils, System.Generics.Collections, ElemTypes, ElemShadow;

function SumAlias(const pTokens: TTokList): Integer;
begin
  Result:= 0;
  for var i:= 0 to pTokens.Count - 1 do
    Inc(Result, pTokens[i].Kind);
end;

function GetList: TTokList;
begin
  Result:= GToks;
end;

procedure RunAll;
begin
  GToks:= TTokList.Create;
  GDirect:= TList<ElemTypes.TTok>.Create;
  GNested:= TList<TArray<ElemTypes.TTok>>.Create;
  GToks.Add(MakeTok(1));
  GDirect.Add(MakeTok(2));
  WriteLn('alias ', SumAlias(GToks));
  WriteLn('unit alias ', GToks[0].Kind);
  WriteLn('unit direct ', GDirect[0].Kind);
  WriteLn('hard ', GetList()[0].Hard);

  var Others:= TList<TOtherRec>.Create;
  var Other: TOtherRec;
  Other.Kind:= 3;
  Others.Add(Other);
  WriteLn('other ', Others[0].Kind);
  Others.Free;

  var Things:= TObjectList<TThing>.Create(True);
  Things.Add(TThing.Create);
  Things[0].Kind:= 4;
  Things[0].Ping;
  Things[0].Ping();
  WriteLn('thing ', Things[0].Kind, ' ', Things[0].Tally);

  var Dict:= TDictionary<string, TThing>.Create;
  Dict.Add('a', Things[0]);
  WriteLn('dict ', Dict['a'].Kind);
  Dict.Free;

  var Holder:= THolder.Create;
  Holder.Toks.Add(MakeTok(5));
  WriteLn('prop ', Holder.Toks[0].Kind);
  WriteLn('field ', Holder.FToks[0].Kind);
  var Holders:= TObjectList<THolder>.Create(True);
  Holders.Add(Holder);
  WriteLn('chain ', Holders[0].Toks[0].Kind);
  Holders.Free;

  GNested.Add([MakeTok(6)]);
  WriteLn('nested ', GNested[0][0].Kind);
  GNested.Free;

  { string has no member Length a project class could own: TThing.Length is not this occurrence. }
  var Names:= TList<string>.Create;
  Names.Add('abc');
  WriteLn('string ', Names[0].Length);
  Names.Free;
  WriteLn('thing length ', Things[0].Length);

  var Box:= TBox<TThing>.Create;
  Box.FL:= TList<TThing>.Create;
  Box.FL.Add(Things[0]);
  WriteLn('box ', Box.First);
  Box.FL.Free;
  Box.Free;

  RunShadow;

  Things.Free;
  GDirect.Free;
  GToks.Free;
end;

end.