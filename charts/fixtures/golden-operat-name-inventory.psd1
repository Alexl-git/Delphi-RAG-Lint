@{
  # AC-5: a node is MATCHED when a step, facet or condition is anchored in File and its routine
  # or text carries Symbol; DISCLOSED when a STOPS reason carries Symbol.
  Nodes = @(
    @{ N = 1;  Name = 'FMTOperation (TFDMemTable)';         File = 'Blueprint4.ViewModel.pas'; Symbol = 'FMTOperation';        Golden = 78 }
    @{ N = 2;  Name = 'FDsrOperation (TDataSource)';        File = 'Blueprint4.ViewModel.pas'; Symbol = 'FDsrOperation';       Golden = 99 }
    @{ N = 3;  Name = 'AfterPost wiring';                   File = 'Blueprint4.ViewModel.pas'; Symbol = 'AfterPost';           Golden = 639 }
    @{ N = 4;  Name = 'DoAfterPostOperation';               File = 'Blueprint4.ViewModel.pas'; Symbol = 'DoAfterPostOperation'; Golden = 277 }
    @{ N = 5;  Name = 'SendDeltaOperation';                 File = 'Blueprint4.ViewModel.pas'; Symbol = 'SendDeltaOperation';  Golden = 279 }
    @{ N = 6;  Name = 'cmdDelta payload contract';          File = 'Pipes.Protocol.pas';       Symbol = 'cmdDelta';            Golden = 389 }
    @{ N = 7;  Name = 'TPipeSessionBuilder.HandleDelta';    File = 'uPipeSessionBuilder.pas';  Symbol = 'HandleDelta';         Golden = 63 }
    @{ N = 8;  Name = 'TGenericTableRoute.HandleDelta';     File = 'uGenericTableRoute.pas';   Symbol = 'HandleDelta';         Golden = 75 }
    @{ N = 9;  Name = 'TDatasetsDef.GetTable';              File = 'uDatasetsDef.pas';         Symbol = 'GetTable';            Golden = 59 }
    @{ N = 10; Name = 'FROM FIB$DATASETS_INFO';             File = 'uDatasetsDef.pas';         Symbol = 'FIB$DATASETS_INFO';   Golden = 130 }
    @{ N = 11; Name = 'TGenericApplyContext.HandleUpdateRecord'; File = 'uGenericTableRoute.pas'; Symbol = 'HandleUpdateRecord'; Golden = 63 }
    @{ N = 12; Name = 'OPERAT.NAME (column)';               File = 'MS1.SQL';                  Symbol = 'OPERAT.NAME';         Golden = 2808 }
    @{ N = 13; Name = 'post-commit broadcast';              File = 'uBroadcastServer.pas';     Symbol = 'PushTableChanged';    Golden = 120 }
    @{ N = 14; Name = 'LoadAllForFolder';                   File = 'Blueprint4.ViewModel.pas'; Symbol = 'LoadAllForFolder';    Golden = 321 }
    @{ N = 15; Name = 'LoadOneTable';                       File = 'Blueprint4.ViewModel.pas'; Symbol = 'LoadOneTable';        Golden = 266 }
    @{ N = 16; Name = 'cmdTableLoad payload contract';      File = 'Pipes.Protocol.pas';       Symbol = 'cmdTableLoad';        Golden = 57 }
    @{ N = 17; Name = 'TPipeSessionBuilder.HandleTableLoad'; File = 'uPipeSessionBuilder.pas'; Symbol = 'HandleTableLoad';     Golden = 59 }
  )
  # AC-7: a guard is MATCHED when a WHEN/UNLESS condition is anchored at File:Line and its
  # verbatim text contains Word; DISCLOSED when a STOPS reason names Word.
  Guards = @(
    @{ G = 1;  Name = 'FSuppressEvents';             File = 'Blueprint4.ViewModel.pas'; Line = 3950; Word = 'FSuppressEvents' }
    @{ G = 2;  Name = 'ChangeCount';                 File = 'Blueprint4.ViewModel.pas'; Line = 3973; Word = 'ChangeCount' }
    @{ G = 3;  Name = 'FConn.Connected (write)';     File = 'Blueprint4.ViewModel.pas'; Line = 3974; Word = 'FConn.Connected' }
    @{ G = 4;  Name = 'table name not empty';        File = 'uGenericTableRoute.pas';   Line = 411;  Word = "TableName = ''" }
    @{ G = 5;  Name = 'delta stream not empty';      File = 'uGenericTableRoute.pas';   Line = 421;  Word = 'Length(StreamBytes) = 0' }
    @{ G = 6;  Name = 'definition exists (delta)';   File = 'uGenericTableRoute.pas';   Line = 431;  Word = 'GetTable' }
    @{ G = 7;  Name = 'deserialization succeeds';    File = 'uGenericTableRoute.pas';   Line = 446;  Word = 'LoadFromStream' }
    @{ G = 8;  Name = 'SQL not empty';               File = 'uGenericTableRoute.pas';   Line = 196;  Word = "SQL = ''" }
    @{ G = 9;  Name = 'FConn.Connected (read)';      File = 'Blueprint4.ViewModel.pas'; Line = 1133; Word = 'FConn.Connected' }
    @{ G = 10; Name = 'definition exists (load)';    File = 'uPipeSessionBuilder.pas';  Line = 525;  Word = 'GetTable' }
    @{ G = 11; Name = 'WHERE is safe';               File = 'uPipeSessionBuilder.pas';  Line = 549;  Word = 'TryBuildSafeWhere' }
    @{ G = 12; Name = 'response is rspData';         File = 'Blueprint4.ViewModel.pas'; Line = 1137; Word = 'rspData' }
  )
}
