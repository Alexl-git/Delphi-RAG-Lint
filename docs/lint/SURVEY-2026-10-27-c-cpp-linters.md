# Survey: C/C++ static-analysis concepts vs drag-lint (195 rules)

Date 2026-10-27. Method: concept-grouped. Our coverage judged from rule ids + titles in our-rules.tsv and the
MISSING-FEATURES.md / BACKLOG.md text (titles are short; where a rule's exact reach is unknown the status is PARTIAL?).
Tool rule ids marked (fetched) were read from the official lists on 2026-10-27 (clang-tidy checks list, PVS-Studio
warnings page, Cppcheck home). Other ids (Cppcheck ListOfChecks, CSA, GCC, Coverity, Sonar, PC-lint, MISRA, CERT) are
from memory and not re-verified; treat the exact id spelling as approximate, the concept as reliable.
Status: HAVE / PARTIAL / FILED / NEW. Value = real bugs vs noise. Feasibility: easy = AST/syntax, medium = needs
type/resolution/index, hard = data-flow / path sensitivity. "Delphi example" cells use " / " for line breaks.

## 1. Concepts (NEW-high first, then NEW-med, NEW-low, PARTIAL, FILED, HAVE)

| # | concept | tools (example id) | status | our id | Delphi example | value | feas |
|---|---|---|---|---|---|---|---|
| 1 | Owned field created in a ctor/method but never freed in Destroy (or no destructor) | Coverity CTOR_DTOR_LEAK; clang-tidy cppcoreguidelines-owning-memory (analog) | NEW | (object-leak is locals only) | FList := TList.Create; in Create / Destroy lacks FList.Free (or no Destroy) | high | medium |
| 2 | Raw memory op with wrong size: Length(S) without SizeOf(Char), SizeOf(ref), FillChar/Move over a managed record | clang-tidy bugprone-suspicious-memset-usage, bugprone-undefined-memory-manipulation (fetched); PVS V635, V512 (fetched); Coverity SIZEOF_MISMATCH | NEW | - | Move(S[1], Buf, Length(S)) / FillChar(Rec, SizeOf(Rec), 0) where Rec has a string field | high | medium |
| 3 | Search result (-1 from IndexOf, 0 from Pos) used as index / argument without a check | Coverity NEGATIVE_RETURNS; cppcheck negativeIndex | NEW | - | L[L.IndexOf(X)] / P := Pos('x', S); S := Copy(S, 1, P - 1) | high | medium (direct form easy, via variable needs flow) |
| 4 | Dereference of a call result that can be nil (FindComponent, Find, user fn that assigns Result := nil on some path) without a check | Coverity NULL_RETURNS; CSA core.NullDereference; GCC -Wnull-dereference; Sonar cpp:S2259 | NEW | not-assigned-interface covers only never-assigned locals | FindComponent('Edit1').Text := '' | high | medium (user-fn variant uses index Result-assignment facts) |
| 5 | Variable dereferenced / indexed BEFORE its nil or bounds check (the check proves it can be nil) | PVS V595 (fetched), V781; Coverity REVERSE_INULL; cppcheck nullPointerRedundantCheck, arrayIndexThenCheck | NEW | - | X.Run; if Assigned(X) then ... / if (A[I] > 0) and (I < Length(A)) | high | medium (CFG engine exists) |
| 6 | Manual Free of an object already owned by a container (OwnsObjects=True list/dict) | PVS V1006 (fetched; analog: two owners of one pointer); cppcoreguidelines-owning-memory | NEW | double-free is same-variable only | L := TObjectList.Create(True); L.Add(O); O.Free; | high | medium (owning flag from ctor arg + type) |
| 7 | Copy-paste typo in near-identical consecutive statements (x/y, Left/Top mixed up) | PVS V525, V537, V501 (fetched); Coverity COPY_PASTE_ERROR | NEW | duplicate-code is clone detection, not near-miss typos | R.Left := A.Left; R.Top := A.Left; | high | medium (heuristic: same shape, one operand repeated) |
| 8 | Multiplication in Integer then widened to Int64 (overflow before widening) | clang-tidy bugprone-implicit-widening-of-multiplication-result, bugprone-misplaced-widening-cast (fetched); cppcheck truncLongCastAssignment; PVS V1028 (fetched); PC-lint 679 | NEW | nativeint-truncation covers casts to 32-bit only | Total: Int64 := Cnt * Size; (both Integer) | high | medium (operand types) |
| 9 | Collection mutated while iterated (Delete/Remove/Add inside for-in or index loop over the same list) | cppcheck invalidContainer; Coverity INVALIDATE_ITERATOR | NEW | - | for I := 0 to L.Count - 1 do if Bad(L[I]) then L.Delete(I); | high | easy-medium (same receiver text in loop head and body) |
| 10 | Exception can escape a context that swallows or mishandles it: TThread.Execute (stored silently in FatalException), destructors, finalization | clang-tidy bugprone-exception-escape (fetched); cppcheck exceptThrowInDestructor; CERT DCL57-CPP | NEW | raise-in-finally is a different place | procedure TW.Execute; begin DoWork; end; (no try/except) / destructor with a bare raise | high | easy |
| 11 | Infinite loop: loop condition variables not changed in the body, no Exit/Break | clang-tidy bugprone-infinite-loop (fetched); PVS V654 (fetched); PC-lint 441 | NEW | loop-executes-at-most-once is the opposite | while I < N do Process(Items[0]); (I never changes) | med | medium |
| 12 | Unsigned value compared < 0 / >= 0, or unsigned Count - 1 wrap in for/while | GCC -Wtype-limits; cppcheck unsignedLessThanZero; PVS V605, V658 (fetched); PC-lint 568 | NEW | - | var C: Cardinal; if C < 0 then ... / for I := 0 to UCount - 1 do | med | medium |
| 13 | shl/shr by >= type width, or 32-bit shl whose result is widened (1 shl 40, Int64 := 1 shl 31) | PVS V610, V629, V1093 (fetched); cppcheck shiftTooManyBits; CERT INT34-C | NEW | - | Mask: Int64 := 1 shl 40; | med | medium |
| 14 | Integer division where a float result was intended | clang-tidy bugprone-integer-division (fetched); PVS V1064, V636 (fetched) | NEW | - | Pct: Double := Done div Total * 100; | med | medium |
| 15 | Misleading indentation (statement indented as if inside then/else/loop but is not) | clang-tidy readability-misleading-indentation (fetched); GCC -Wmisleading-indentation; PVS V640 (fetched); PC-lint 725 | NEW | multiple-statements-per-line is unrelated | if Ok then / Log('a'); / Log('b'); (second line indented as if guarded) | med | easy |
| 16 | Exception object freed inside its own handler (RTL frees it) | CERT ERR61-CPP (cert-err61-cpp fetched; catch by reference, do not own); analog | NEW | - | on E: Exception do begin Log(E.Message); E.Free; end; | med | easy |
| 17 | Mismatched allocation/deallocation pair | CSA unix.MismatchedDeallocator; cppcheck mismatchAllocDealloc; PVS V611, V1005 (fetched) | NEW | - | GetMem(P, 16); ... Dispose(P); / New(P); FreeMem(P); | med | easy-medium |
| 18 | Local/parameter shadows a class member, inherited member or unit global | GCC -Wshadow; cppcheck shadowVariable; Sonar cpp:S1117; PC-lint 578 | NEW | with-hides-outer-symbol covers `with` only; confusable-identifier is underscores only | procedure TF.Go; var Name: string; (hides TForm.Name) | med | medium |
| 19 | Suspicious call arguments: same argument twice, or arguments matching parameter names in swapped order | clang-tidy bugprone-swapped-arguments, readability-suspicious-call-argument (fetched); PVS V549 (fetched); Coverity SWAPPED_ARGUMENTS | NEW | - | Max(A, A) / Rect(Bottom, Top, ...) | med | medium |
| 20 | Pointer to a local (or PChar of a temporary/local string) escapes the routine | GCC -Wreturn-local-addr; CSA core.StackAddressEscape; PVS V506, V558 (fetched) | NEW | - | Result := PChar(S); (S local) / FPtr := @LocalBuf; | med | easy-medium |
| 21 | Anonymous method capturing a for-loop variable and handed to TTask/TThread (sees final value) | PVS V1047 (fetched; lifetime analog); cppcheck danglingLifetime | NEW | - | for I := 1 to 4 do TTask.Run(procedure begin Use(I) end); | med | medium |
| 22 | Weak crypto primitive (MD5/SHA1/DES/ECB) | Sonar cpp:S4790, S5547; Coverity RISKY_CRYPTO | NEW | weak-random-for-security is RNG only | THashMD5.GetHashString(Pwd) | med | easy |
| 23 | TLS/certificate validation disabled | Sonar cpp:S4830; CWE-295 | NEW | - | IdSSL.SSLOptions.VerifyMode := []; / OnVerifyPeer handler: Result := True | med | easy-medium |
| 24 | Non-literal format string with no arguments (user text with % crashes or leaks) | GCC -Wformat-security, -Wformat-nonliteral; CERT FIO30-C | NEW | format-argument-count assumes a literal | Msg := Format(UserText, []); | med | easy |
| 25 | Handle/library result used without validity check | PVS V1095 (fetched); CERT ERR33-C (cert-err33-c fetched) | NEW | - | H := CreateFile(...); ReadFile(H, ...); / P := GetProcAddress(L, 'X'); P(); | med | medium |
| 26 | Side-effecting call repeated in one expression / argument list (evaluation order unspecified) | CERT EXP50-CPP; GCC -Wsequence-point; clang-tidy bugprone-macro-repeated-side-effects (analog); MISRA 13.2 | NEW | query-name-with-effect has the effect engine, rule absent | Format('%d %d', [Next, Next]) / S := ReadTok + ReadTok; | med | medium (reuse effect-proven engine) |
| 27 | 0-based indexing assumption on 1-based strings / APIs (S[0], loop 0..Length-1 indexing S, Copy/Delete with index 0) | cppcheck arrayIndexOutOfBounds (analog); PVS V557 (analog) | NEW | off-by-one-count checks only the upper bound | for I := 0 to Length(S) - 1 do if S[I] = ',' then ... | med | medium |
| 28 | Local record only partly initialised then read whole | cppcheck uninitStructMember; GCC -Wmaybe-uninitialized; cppcoreguidelines-pro-type-member-init | NEW | used-before-assignment is whole-variable | var R: TRec; R.A := 1; Save(R); (R.B garbage) | med | medium |
| 29 | Large local array / ShortString (stack overflow, esp. recursion or threads) | GCC -Wframe-larger-than, -Wstack-usage; PVS V505 (fetched) | NEW | - | var Buf: array[0..1048575] of Byte; | med | easy-medium |
| 30 | Unsynchronised shared state in threads / double-checked-locking singleton | PVS V1036 (fetched); Coverity MISSING_LOCK, race family | NEW | ui-access-in-thread, criticalsection-not-released are separate | if FInst = nil then begin Lock; if FInst = nil then FInst := TFoo.Create; ... | med | hard |
| 31 | Field freed outside Destroy without nil-ing (dangling field) | CERT MEM01-C; Coverity USE_AFTER_FREE | NEW | use-after-free (locals/same routine); unprotected-object-free | procedure TF.Reset; begin FConn.Free; end; (used later) | med | easy-medium |
| 32 | for-loop control variable unused in the body / loop-invariant assignment | PVS V1021 (fetched, same value each iteration) | NEW | - | for I := 0 to N - 1 do Sum := Sum + A[0]; | med | easy-medium |
| 33 | Recursion: unconditional (every path recurses) is a bug; any recursion is a safety-profile finding | GCC -Winfinite-recursion; clang-tidy misc-no-recursion (fetched); MISRA 17.2 | NEW | property-references-itself is property-only | procedure A; begin A; end; | med (unconditional) / low (any) | medium (call graph exists) |
| 34 | Float loop counter | CSA security.FloatLoopCounter; bugprone-float-loop-counter, cert-flp30-c (fetched); PVS V1034 | NEW | float-equality-comparison is `=` only | while X < 1.0 do begin ...; X := X + 0.1; end; | low | easy-medium |
| 35 | Constructor invoked as a plain call inside a constructor | clang-tidy bugprone-undelegated-constructor (fetched) | NEW | missing-inherited-ctor is the inverse | constructor TA.Create; begin Create(0); end; | low | easy |
| 36 | Call to qualified ancestor skips an intermediate override | clang-tidy bugprone-parent-virtual-call (fetched) | NEW | inherited-bare is different | TBase.Foo; inside TLeaf.Foo whose parent is TMid | low | easy-medium |
| 37 | Redundant trailing control flow (Exit as last statement, Continue at loop end) | clang-tidy readability-redundant-control-flow (fetched) | NEW | code-after-exit is the opposite | procedure P; begin Work; Exit; end; | low | easy |
| 38 | Collapsible nested if (if A then if B then) | Sonar cpp:S1066; clang-tidy readability-redundant-nested-if (fetched) | NEW | - | if A then if B then Go; | low | easy |
| 39 | Mixed and/or without parentheses | GCC -Wparentheses; cppcheck clarifyCondition; MISRA 12.1 | NEW | redundant-parentheses is the opposite | if A and B or C then | low | easy |
| 40 | Nested inline-if expression (if..then..else inside if..then..else) | clang-tidy readability-avoid-nested-conditional-operator (fetched) | NEW | - | X := if A then 1 else if B then 2 else 3; | low | easy |
| 41 | Single statement body without begin/end | clang-tidy readability-braces-around-statements (fetched); MISRA 15.6 | NEW | - | if Ok then Log('a'); (style; ship OFF) | low | easy |
| 42 | Property setter does not write its backing field / getter returns another field | PVS V524/V525 class (analog); no direct C rule found | NEW | - | procedure SetX(V: Integer); begin FY := V; end; | low | medium |
| 43 | Parameter mode could be const (string/record/interface by value, var never written) | clang-tidy performance-unnecessary-value-param, readability-non-const-parameter (fetched); cppcheck passedByValue, constParameter; PC-lint 818 | NEW | - | procedure P(S: string); (S only read) | low | medium |
| 44 | Assignment to a value parameter | MISRA 17.8 | NEW | - | procedure P(N: Integer); begin N := N + 1; end; | low | easy |
| 45 | Declaration vs implementation parameter names differ | clang-tidy readability-inconsistent-declaration-parameter-name (fetched) | NEW | param-name-prefix is naming only | declared (AIndex) / implemented (Idx) | low | easy |
| 46 | Randomize missing / called repeatedly; same sequence every run | clang-tidy bugprone-random-generator-seed (fetched), cert-msc32-c (fetched); PVS V1057 (fetched) | NEW | weak-random-for-security | Random used, no Randomize in project / Randomize inside a loop | low | easy-medium (project-wide) |
| 47 | Invisible / bidirectional / control characters in source or strings | clang-tidy misc-misleading-bidirectional (fetched); PVS V538, V1076 (fetched) | NEW | encoding guards live outside the lint rules | string literal containing U+202E | low | easy |
| 48 | Warnings or range/overflow checks switched off by directive | Sonar cpp:S1309; MISRA pragma-use directives; PC-lint | NEW | - | {$WARNINGS OFF} / {$Q-} / {$R-} | low | easy |
| 49 | Overflow check done after the operation | PVS V1012 (fetched) | NEW | - | if A + B < A then Overflow; | low | easy |
| 50 | Manual rounding idiom Trunc(x + 0.5) | clang-tidy bugprone-incorrect-roundings (fetched) | NEW | - | N := Trunc(X + 0.5); | low | easy |
| 51 | Nested loops reuse the same index variable | PVS V535 (fetched); PC-lint 445 | NEW | - | for I := ... do for I := ... do (compiler may already reject; verify) | low | easy |
| 52 | Procedural/event field called without Assigned check | CSA core.CallAndMessage; PVS V516 (analog) | NEW | - | FOnChange(Self); | low | medium (noisy) |
| 53 | `Self = nil` / Assigned(Self) | PVS V704 (fetched) | NEW | - | if Self = nil then Exit; | low | easy |
| 54 | nil-check after Create (always non-nil; ctor raises) | PVS V668 (fetched) | NEW | nil-comparison is style only | X := TFoo.Create; if X = nil then ... | low | easy |
| 55 | PChar compared with = (pointer compare, string intended) | clang-tidy bugprone-suspicious-string-compare (fetched) | NEW | string-equality-comparison is string typed | if PChar(A) = PChar(B) then | low | medium |
| 56 | Wait without re-check loop (spurious wake-up) | clang-tidy bugprone-spuriously-wake-up-functions, cert-con54-cpp (fetched); PVS V1089 | NEW | - | if not Done then Mon.Wait(...) instead of while | low | easy |
| 57 | Lock order inversion / double lock | Coverity ORDER_REVERSAL; CSA | NEW | criticalsection-not-released | A.Enter; B.Enter ... / B.Enter; A.Enter | low | hard |
| 58 | Unit initialization-order dependency (init section uses a global set by a later unit) | clang-tidy misc-static-initialization-cycle (fetched); PVS V1092 (fetched) | NEW | circular-uses | initialization section reads another unit's unset global | low | hard |
| 59 | Halt / ExitProcess in library code | MISRA 21.8; CERT ENV32-C | NEW | - | Halt(1) in a non-.dpr unit | low | easy |
| 60 | Raising a class that is not an Exception descendant | clang-tidy bugprone-std-exception-baseclass (fetched); PVS V702 (fetched) | NEW | raise-bare-exception | raise TObject.Create; | low | easy-medium |
| 61 | Override that only calls inherited | cppcheck uselessOverride | NEW | empty-procedure-body | procedure Foo; override; begin inherited; end; | low | easy |
| 62 | File opened read-only then written (mode mismatch) | PVS V1075 (fetched) | NEW | - | S := TFileStream.Create(F, fmOpenRead); S.Write(...) | low | medium |
| 63 | Must-use result ignored: RTL functions and helpers (S.Replace, Trim, TryStrToInt, Stream.Read count, Win32 BOOL) | clang-tidy bugprone-unused-return-value (fetched), cert-err33-c (fetched); PVS V530 (fetched); Coverity CHECKED_RETURN | PARTIAL | discarded-effect-free-result (proven pure only), function-result-ignored (same-unit, OFF) | S.Replace('a','b'); / TryStrToInt(T, N); / Stream.Read(B, 4); | high | easy-medium (curated callee list + resolution) |
| 64 | Acquire/release pairing beyond locks and datasets (BeginUpdate/EndUpdate, DisableControls/EnableControls, StartTransaction/Commit-Rollback, Screen.Cursor restore, BeginRead/EndRead) not in try/finally | CSA unix.Stream; Coverity RESOURCE_LEAK; PC-lint 429 | PARTIAL | criticalsection-not-released (locks), dataset-open-without-close; BACKLOG sec 4 lists Enter/Leave and file pairing | Q.DisableControls; ...; Q.EnableControls; (not in finally) | high | easy-medium (configurable pair table) |
| 65 | Taint: external input (ParamStr, Request, ReadLn, Indy) reaches a sink | CSA alpha.security.taint; Coverity TAINTED_*; PVS V1010 (fetched); GCC -fanalyzer tainted-* | PARTIAL | sql-injection-concat, path-traversal, unsafe-shellexecute (syntactic sinks, no source tracking) | Cmd := Request.Params[0]; ShellExecute(0, 'open', PChar(Cmd), ...) | high | hard |
| 66 | Nil path: nil is tested, the branch does not leave, code dereferences anyway | Coverity FORWARD_NULL; CSA core.NullDereference | PARTIAL? | not-assigned-interface only | if X = nil then Log('x'); X.Run; | high | medium-hard |
| 67 | Implicit narrowing assignment (Int64/UInt64/NativeInt to Integer/Word/Byte, Double to Single) | clang-tidy bugprone-narrowing-conversions (fetched); GCC -Wconversion; PVS V1029 (fetched); PC-lint 569 | PARTIAL | nativeint-truncation, win64-pointer-cast (explicit casts only) | I := Stream.Size; (Int64 to Integer) | med | medium |
| 68 | Contradictory / tautological / redundant conditions on one variable (x>5 and x<3; nested same test; identical test after early Exit) | PVS V547, V560, V637, V571 (fetched); cppcheck incorrectLogicOperator, oppositeInnerCondition, identicalConditionAfterEarlyExit; clang-tidy misc-redundant-expression, bugprone-redundant-branch-condition (fetched) | PARTIAL | constant-condition (literal conditions), repeated-else-if-condition (chain only) | if (X < 3) and (X > 5) then / if A then if A then | med | medium |
| 69 | Identical operands in and/or/xor/- (a and a, a - a) | PVS V501 (fetched); cppcheck duplicateExpression; GCC -Wlogical-op | PARTIAL | comparison-same-operands (comparisons only) | if (A = 1) or (A = 1) then | med | easy |
| 70 | Exception handler order: handler for an ancestor before a descendant | GCC/clang -Wexceptions; CERT ERR54-CPP | PARTIAL | duplicate-exception-handler (same class only) | on E: Exception do ...; on E: EAccessViolation do ... | med | easy-medium (M1 hierarchy) |
| 71 | Division by a variable proven zero on the path; divide before zero-test | CSA core.DivideZero, alpha.core.TestAfterDivZero; cppcheck zerodiv; PVS V609 (fetched) | PARTIAL | division-by-zero-literal | N := 0; R := A div N; / R := A div N; if N = 0 then | med | hard |
| 72 | Override of framework virtuals (Loaded, Notification, CreateParams, KeyDown ...) without inherited | Coverity-style missing-super-call (analog) | PARTIAL | missing-inherited-ctor, missing-inherited-dtor | procedure TC.Loaded; override; begin FInit := True; end; | med | easy (curated list) |
| 73 | Public symbol used only inside its own unit (could be private / implementation-only) | PC-lint 759, 765 | PARTIAL | unused-public-symbol (zero references only); verb uses-audit moves uses, not symbols | interface routine called only in own unit | low | easy (index refs) |
| 74 | Constructed object discarded as a statement (leak) | PVS V603, V596 (fetched); cppcheck leakReturnValNotUsed | PARTIAL | exception-constructed-but-not-raised (exception-looking classes only) | TStringList.Create; | med | easy |
| 75 | Leak by overwriting the only owner before freeing | CSA unix.Malloc (overwrite); PC-lint 423; PVS V701 (analog) | PARTIAL? | object-leak (exit-point leaks; overwrite case unknown) | X := TFoo.Create; X := TFoo.Create; | med | medium |
| 76 | Dead store to element/property/field/map key (not a local) | cppcheck redundantAssignment; Sonar cpp:S4143 | PARTIAL | overwrite-before-read (locals) | D[K] := 1; D[K] := 2; | low | medium |
| 77 | Identical case branches | PVS V1037 (fetched); clang-tidy bugprone-branch-clone (fetched); Sonar cpp:S1871 | PARTIAL | identical-then-else (if only) | case K of 1: A; 2: A; end; | low | easy |
| 78 | Hard cast between provably unrelated classes | PVS V1027 (fetched) | PARTIAL | unsafe-typecast-without-is | TButton(MyEdit) | low | medium |
| 79 | Redundant nil-check before is / as / Free | clang-tidy readability-delete-null-pointer (fetched) | PARTIAL | redundant-assigned-free (Free only) | if (X <> nil) and (X is TFoo) then | low | easy |
| 80 | Boolean assignment collapsible (not only Result) | clang-tidy readability-simplify-boolean-expr (fetched) | PARTIAL | boolean-result-returned-directly (Result only) | if C then F := True else F := False; | low | easy |
| 81 | case over a non-enum without else | clang-tidy bugprone-switch-missing-default-case (fetched); MISRA 16.4 | PARTIAL | exhaustive-enum-case (enums only) | case N of 1: A; 2: B; end; | low | easy |
| 82 | Unicode-confusable identifiers / homoglyphs | clang-tidy misc-confusable-identifiers, misc-misleading-identifier (fetched) | PARTIAL | confusable-identifier (underscore variants only) | Count vs C(Cyrillic o)unt | low | easy |
| 83 | TOCTOU: FileExists then open/read | CERT FIO45-C; Coverity TOCTOU | PARTIAL | stat-gated-destructive (destructive only) | if FileExists(F) then S := TFileStream.Create(F, fmOpenRead) | low | easy-medium |
| 84 | File / handle created without matching close | CSA unix.Stream; GCC -fanalyzer file-leak; cppcheck resourceLeak | FILED | BACKLOG.md sec 4 Resource ("file-not-closed"); MISSING-FEATURES.md sec 5 (object-leak covers owned TObjects) | H := FileOpen(...); no FileClose | med | medium |
| 85 | ParamByName inside a loop | (performance family) | FILED | BACKLOG.md sec 4 FireDAC (`parambyname-in-loop`); sibling field-by-name-in-loop exists | for ... do Q.ParamByName('A').AsInteger := I; | low | easy |
| 86 | Magic string literals | clang-tidy readability-magic-numbers (numbers only); Sonar | FILED | BACKLOG.md sec 4 Maintainability (`magic-string`); magic-literal covers numbers | if Kind = 'ADMIN' then | low | easy |
| 87 | Type punning via variant records / absolute | MISRA 19.2 (unions); CERT EXP39-C | FILED | MISSING-FEATURES.md sec 9 (`variant-record-type-punning`, deferred) | R = record case Boolean of ... | low | hard |
| 88 | Unvalidated deserialization | Sonar; CWE-502 | FILED | MISSING-FEATURES.md sec 10 (`unvalidated-deserialization`, no clean signal) | TJson.JsonToObject on user input | low | hard |
| 89 | Cross-routine object/interface dual ownership; cross-routine field def-use | CSA/Coverity interprocedural | FILED | MISSING-FEATURES.md sec 4 (interface-object-mixing cross-routine) and sec 3 (field def-use tail) | field aliased into interface in one method, freed in another | med | hard |
| 90 | Nested-routine count / too many nested routines | (metrics) | FILED | BACKLOG.md sec 4 Metrics (`too-many-nested-routines`) | - | low | easy |
| 91 | Self-assignment | PVS V570 (fetched); cppcheck selfAssignment | HAVE | self-assignment | X := X; | - | - |
| 92 | Identical then/else | PVS V523 (fetched); GCC -Wduplicated-branches | HAVE | identical-then-else | if C then A else A | - | - |
| 93 | Repeated condition in else-if chain | PVS V517 (fetched); GCC -Wduplicated-cond; cppcheck multiCondition | HAVE | repeated-else-if-condition | - | - | - |
| 94 | Same operands in comparison | PVS V501; cppcheck duplicateExpression | HAVE | comparison-same-operands | - | - | - |
| 95 | Unreachable code | PVS V551; GCC -Wunreachable-code; cppcheck unreachableCode | HAVE | code-after-exit | - | - | - |
| 96 | Use after free / double free | CSA cplusplus.NewDelete; GCC -fanalyzer | HAVE | use-after-free, double-free | - | - | - |
| 97 | Resource / memory leak (locals) | CSA unix.Malloc; cppcheck memleak; Coverity RESOURCE_LEAK | HAVE | object-leak, unprotected-object-free, create-inside-try | - | - | - |
| 98 | Uninitialised use; missing return value; out param | GCC -Wuninitialized, -Wreturn-type; CSA core.uninitialized.*; PVS V614 (fetched) | HAVE | used-before-assignment, function-result-not-set, out-param-not-set | - | - | - |
| 99 | Dead store, unused variable/parameter/private member | PVS V1001 (fetched); clang-tidy misc-unused-parameters (fetched); CSA deadcode.DeadStores | HAVE | write-only-local, overwrite-before-read, unused-local, unused-parameter, unused-private-member | - | - | - |
| 100 | Empty body / suspicious semicolon / empty catch | PVS V529 (fetched); clang-tidy bugprone-suspicious-semicolon, bugprone-empty-catch (fetched); GCC -Wempty-body | HAVE | empty-conditional, empty-loop-body, empty-except, empty-on-handler, empty-finally, empty-case-branch | - | - | - |
| 101 | Exception constructed but not thrown | PVS V596 (fetched); clang-tidy bugprone-throw-keyword-missing (fetched) | HAVE | exception-constructed-but-not-raised | - | - | - |
| 102 | Throw in finally / control flow in finally / rethrow loses stack / swallowed | CERT ERR family; cppcheck | HAVE | raise-in-finally, control-flow-in-finally, reraise-loses-stack, try-except-swallowed, bare-except | - | - | - |
| 103 | Assert with side effects | clang-tidy bugprone-assert-side-effect (fetched) | HAVE | assert-with-side-effect | - | - | - |
| 104 | Virtual call in constructor; missing virtual destructor | PVS V1053, V599 (fetched); cppcheck virtualCallInConstructor | HAVE | virtual-method-in-constructor, destructor-without-override | - | - | - |
| 105 | Floating-point equality | GCC -Wfloat-equal; PVS V550 (fetched) | HAVE | float-equality-comparison | - | - | - |
| 106 | Division by literal zero | PVS V609; CSA core.DivideZero | HAVE | division-by-zero-literal | - | - | - |
| 107 | Operator-precedence traps (not A = B, not X in S) | PVS V502/V634 (fetched); GCC -Wparentheses | HAVE | not-comparison-precedence, not-in-precedence | - | - | - |
| 108 | goto, with, inline asm, too many exits | MISRA 15.1, 15.5 | HAVE | goto-statement, with-statement, nested-with, with-multiple-items, inline-assembly, too-many-exit-points | - | - | - |
| 109 | Complexity, size, nesting, parameter count, clones | clang-tidy readability-function-cognitive-complexity, function-size (fetched); Sonar S3776, S134; PVS V553, V524 | HAVE | cognitive-complexity, cyclomatic-complexity, method-too-long, deep-nesting, too-many-parameters, too-many-locals, unit-too-large, duplicate-code | - | - | - |
| 110 | Class metrics (CBO, RFC, LCOM, DIT, NOC, fan-in/out) | Sonar/Coverity metrics | HAVE | metrics category (8 rules), god-class | - | - | - |
| 111 | Magic numbers | clang-tidy readability-magic-numbers (fetched) | HAVE | magic-literal, large-magic-number, case-magic-numbers | - | - | - |
| 112 | Naming conventions | clang-tidy readability-identifier-naming, identifier-length (fetched) | HAVE | naming category (10 rules) | - | - | - |
| 113 | Format-string arg count/type | GCC -Wformat; cppcheck wrongPrintfScanfArgNum | HAVE | format-argument-count, format-specifier-type-mismatch | - | - | - |
| 114 | Injection / traversal / shell / credentials / IP / temp file | CERT; Sonar S2068, S1313; CSA security.* | HAVE | sql-injection-concat, path-traversal, unsafe-shellexecute, hardcoded-credential, hardcoded-connection-string, hardcoded-ip-address, insecure-temp-file, dfm-hardcoded-credential | - | - | - |
| 115 | Weak RNG for security | CERT MSC30-C; Sonar S2245; clang-tidy cert-msc30-c (fetched) | HAVE | weak-random-for-security | - | - | - |
| 116 | Unsafe string functions / banned APIs | clang-tidy bugprone-unsafe-functions (fetched); CSA security.insecureAPI | HAVE | unsafe-string-api, deprecated-rtl-function | - | - | - |
| 117 | Pointer-size / Win64 truncation, pointer arithmetic | PVS V1091 (fetched); PC-lint 713 | HAVE | win64-pointer-cast, nativeint-truncation, sizeof-pointer-assumption, pchar-arithmetic | - | - | - |
| 118 | Locale / encoding / lossy conversion | (Delphi-flavoured) | HAVE | locale-sensitive-conversion, default-encoding-io, lossy-cast | - | - | - |
| 119 | Circular dependencies, layering, unused includes, interface-to-implementation moves | clang-tidy misc-header-include-cycle, misc-include-cleaner (fetched) | HAVE | circular-uses, cycle-participant-unit, layering-violation, unused-unit-in-uses, unit-not-in-dpr; verb uses-audit (advisory, not a lint rule) | - | - | - |
| 120 | Reference-count cycle, interface/object mixing | PVS V1006 (analog) | HAVE | interface-reference-cycle, interface-object-mixing (same routine), freeandnil-on-interface | - | - | - |
| 121 | Off-by-one loop bound | PVS V557; cppcheck arrayIndexOutOfBounds (analog) | HAVE | off-by-one-count (upper bound only; see #27 for the 0-based side) | - | - | - |
| 122 | Constant conditions, loop runs once | PVS V547, V1008, V612 (fetched); cppcheck knownConditionTrueFalse (literal only) | HAVE | constant-condition, loop-executes-at-most-once | - | - | - |
| 123 | Redundant cast / parentheses / not-not / boolean compare | clang-tidy readability-redundant-casting, redundant-parentheses (fetched) | HAVE | redundant-cast, redundant-parentheses, redundant-not-not, boolean-comparison-true, redundant-as-tobject | - | - | - |
| 124 | Property accessor recursion | (self-recursive accessor) | HAVE | property-references-itself | - | - | - |
| 125 | Ignored result of effect-free routine | clang-tidy bugprone-unused-return-value | HAVE | discarded-effect-free-result (see #63 for the gap) | - | - | - |
| 126 | Missing inherited in ctor/dtor | (OO hygiene) | HAVE | missing-inherited-ctor, missing-inherited-dtor | - | - | - |
| 127 | Mutable global state | MISRA 8.x; Sonar | HAVE | mutable-global-variable, global-form-variable, duplicate-global-decl | - | - | - |
| 128 | Sleep / UI from worker thread | (Delphi) | HAVE | sleep-in-vcl, ui-access-in-thread | - | - | - |
| 129 | String concat in a loop; FieldByName in a loop | clang-tidy performance-inefficient-string-concatenation (fetched) | HAVE | concat-in-loop, field-by-name-in-loop | - | - | - |
| 130 | Commented-out code, TODO | PVS V628 (fetched); Sonar S125, S1135 | HAVE | commented-out-code, compiler-magic-comments | - | - | - |
| 131 | IFDEF with undefined / platform-divergent symbol | MISRA 20.x; PC-lint | HAVE | ifdef-undefined-symbol, platform-divergent-define | - | - | - |
| 132 | Enum persisted by ordinal; exhaustive enum switch | GCC -Wswitch | HAVE | enum-ordinal-persisted, exhaustive-enum-case, enum-bare-read-scoped | - | - | - |
| 133 | Debug output left in code; Assert without message | (hygiene) | HAVE | outputdebugstring, writeln-in-source, assert-call | - | - | - |
| 134 | Destructive act gated on a stat check | CERT FIO | HAVE | stat-gated-destructive | - | - | - |

Notes on ranking: NEW-high rows 1-10 are where C/C++ tools find the most real bugs and Delphi has a direct form with
no compiler diagnostic. Rows 1, 3, 5, 9 and 10 need nothing beyond the existing index + AST + CFG engine.
Rows 19 and 26 depend on resolution; row 26 can reuse the "PROVEN effect" engine behind query-name-with-effect.
Rows 1, 3, 27 and 42 are Delphi-driven ideas whose closest C tool rule is only an analogy; marked as such.
Where Delphi's compiler already rejects the construct (assignment in condition, duplicate case labels, constant
array index out of range, hiding a virtual method), the theme is in section 2 rather than a row.

## 2. Dropped themes (no Delphi analogue or compiler-covered)

- Preprocessor macro abuse (macro-parentheses, multiple-statement-macro, include guards, trigraphs, suspicious-include, redundant-preprocessor)
- Header hygiene: definitions-in-headers, anonymous namespace in header, forward-declaration-namespace, global object in header
- C pointer arithmetic on arrays, array-to-pointer decay, multi-level pointer conversion, pointer-to-member compares, function-pointer alignment casts
- Templates: SFINAE, enable_if, CRTP, forwarding references, fold-init-type, tagged unions, concepts
- Move semantics and rvalue rules (use-after-move, move-const-arg, no-automatic-move)
- Smart-pointer API misuse (shared_ptr/unique_ptr array mismatch, make_shared); Delphi ARC interfaces covered by interface rules
- Copy/move constructors, rule of three/five, operator= conventions, slicing (Delphi classes are references; records have no user copy ctor)
- noexcept / exception specifications, throw by value / catch by reference, bad_alloc handling (Delphi ctors raise EOutOfMemory)
- Assignment inside a condition and = vs == mixups (Pascal separates := and =)
- Duplicate case labels, inverted case range, missing break / fallthrough (Pascal case has none; dups are compile errors)
- printf-family security (scanf widths, %n), POSIX/signal handler rules, setjmp/longjmp, fork/exec, errno
- C++-specific concurrency wrappers (std::thread detach, condition-variable wrappers, mutex wrapper names, launch policy)
- Type hygiene already enforced by Delphi (implicit bool conversion, enum-to-bool, signed char misuse, string literal embedded NUL)
- Constant array index out of bounds (compile error in Delphi); dynamic-bounds overrun needs value analysis, not worth it
- Variable-scope narrowing (cppcheck variableScope), isolate-declaration; style only
- Hiding a base virtual with a same-name method (virtual-near-miss): Delphi compiler warns W1010
- ODR/ABI items: enum-size, trivially-destructible, struct padding, alignment
- Licence/copyleft header checks (V1042), Unreal/Qt specific checks, DllMain rules
- Sensitive-memory wiping (V597, V1072): Delphi strings are shared; low signal

## 3. Sources

Fetched 2026-10-27:
- https://clang.llvm.org/extra/clang-tidy/checks/list.html (bugprone, cert, misc, performance, readability lists)
- https://pvs-studio.com/en/docs/warnings/ (V5xx, V6xx, V7xx, V10xx titles; the V3xxx C# and V2xxx Java ranges not read)
- https://cppcheck.sourceforge.io/ (categories only; per-check list not fetched)
Not fetched, from memory (verify ids before quoting externally):
- https://sourceforge.net/p/cppcheck/wiki/ListOfChecks/
- https://clang.llvm.org/docs/analyzer/checkers.html
- https://gcc.gnu.org/onlinedocs/gcc/Warning-Options.html and https://gcc.gnu.org/onlinedocs/gcc/Static-Analyzer-Options.html
- https://www.misra.org.uk/ (MISRA C:2012 / C++:2023, rule themes only)
- https://wiki.sei.cmu.edu/confluence/display/c and .../cplusplus (CERT C / C++)
- https://rules.sonarsource.com/cpp/ (cpp:S...)
- https://pclintplus.com/ (PC-lint Plus message list)
- Coverity checker reference (CHECKED_RETURN, NULL_RETURNS, FORWARD_NULL, REVERSE_INULL, CTOR_DTOR_LEAK, NEGATIVE_RETURNS, SIZEOF_MISMATCH, COPY_PASTE_ERROR, SWAPPED_ARGUMENTS, INVALIDATE_ITERATOR, ORDER_REVERSAL)
Prior work read: C:\Projects\Delphi-RAG-lint\docs\lint\MISSING-FEATURES.md (full), BACKLOG.md (sec 4 rule-idea backlog plus grep for ~25 concepts; the 520 KB resume log was not read end to end).
