program SolveConfig;

{ check-init fixture solve-config (lane HBTAIL, H-CONFIG of lane HBSOLVER): no callee below has source in
  the index. The answer is recorded ONCE per project in _D-RAG\drag-lint-project.json under
  checkInit.callees: ReadExternal = reads, LoadExternal = sets. "Other.OtherExternal" is a
  QName key: the call names only OtherExternal, so the qualifier cannot be checked and the key does not
  apply (GCfgNone keeps the UNKNOWN-CALLEE warning). "BogusExternal": "maybe" is no answer (ignored).
  GCfgMark: the line marker wins over the project entry (config says reads, the line says sets). }

uses
  scfgData in 'scfgData.pas';

begin
  ReadExternal(GCfgRead); // CALL-READ
  LoadExternal(GCfgSet); // CALL-SET
  OtherExternal(GCfgNone); // CALL-NONE
  BogusExternal(GCfgBogus); // CALL-BOGUS
  ReadExternal(GCfgMark); // dl:callee-sets
  UseAll;
end.
