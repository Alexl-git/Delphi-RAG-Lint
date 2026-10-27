# Standards survey 2026-10-27 -- drag-lint (195 rules) vs CWE, SEI CERT, MISRA, Clippy, DerScanner

Caveats
* Coverage judged from rule TITLES in our-rules.tsv, not rule code. "?" = from memory, not fetched.
* Status tokens: HAVE / PARTIAL / NEW. "NEW*" = NEW but already listed in the earlier surveys
  (SURVEY-2026-10-27-rule-gaps.md "S1 #n", SURVEY-2026-10-27-c-cpp-linters.md "C #n"); counted separately.
* Feasibility: easy = AST/token; medium = types/index/CFG; hard = data-flow/taint.
* Fetched (primary): CWE Top 25 2025 page, CWE-1305, CWE-1340, SEI CERT C rules index,
  Clippy index (first 100k chars only), derscanner.com home. Everything else is memory.

## A. CWE

Lists fetched: 2025 Top 25 (cwe.mitre.org/top25/archive/2025), CWE-1305 (CISQ quality measures:
Reliability 1306, Maintainability 1307, Security 1308; the performance part was not read, so performance ids are "?"),
CWE-1340 (CISQ data protection, 89 members). CWE-1000/699 not read (too broad; the CISQ views are the
curated code-level subset). Delphi is memory safe for strings/dyn arrays/interfaces, not for objects,
pointers, PChar, GetMem, Move: so memory CWEs map to few, manual-memory rules.

| CWE | Name (short) | Our rule | Status | Delphi example | Feas |
|---|---|---|---|---|---|
| 89 | SQL injection (Top25 #2) | sql-injection-concat | PARTIAL | `Q.SQL.Text := 'x='+Edit1.Text`; Format-built SQL, SQL.Add concat | medium |
| 22/23/36 | Path traversal (#6) | path-traversal | HAVE | `LoadFromFile(Dir + Name)` | medium |
| 78/77/88 | OS/command/argument injection (#9,#23) | unsafe-shellexecute | HAVE | `ShellExecute(0,'open','cmd','/c '+S,...)` | easy |
| 416 | Use after free (#7) | use-after-free | HAVE | `O.Free; O.Foo` | medium |
| 415 | Double free | double-free | HAVE | `O.Free; O.Free` | medium |
| 476 | NULL deref (#13) | not-assigned-interface, unsafe-typecast-without-is | PARTIAL | `FindComponent('X').Tag` (S1 #7) | medium |
| 787/125/120/121/122/119 | OOB write/read, buffer overflow (#5,#8,#11,#14,#16) | unsafe-string-api, pchar-arithmetic | PARTIAL | `StrCopy(Buf, S)`; `Buf[I]` past array | medium |
| 787/805 | Wrong size to Move/FillChar/ReadBuffer | - | NEW* S1 #2 | `Move(S[1],B,Length(S))` no SizeOf(Char) | medium |
| 787 | Constant index outside static array/string | - | NEW | `A[10]` on `array[0..9]` | easy |
| 129/190/787 | Range/overflow checks turned off | - | NEW* C #48 | `{$R-}` `{$Q-}` | easy |
| 121/770 | Huge stack array / unbounded allocation | - | NEW | `var B: array[0..4194303] of Byte;`; `SetLength(A, Stream.ReadInt)` | easy / medium |
| 134 | Externally controlled format string | format-argument-count (literals only) | NEW* C #24 | `Format(UserText, [])` | easy |
| 94 | Code injection | - | NEW | script engine `Eval(S + x)`, `TScriptControl.AddCode` | easy-medium (low value) |
| 79 | XSS (#1) | - | NEW | WebBroker `Response.Content := '<p>'+Request.QueryFields.Values['q']` | hard (taint) |
| 502 | Deserialization (#15) | - | NEW (filed: MISSING-FEATURES sec 10) | `TJson.JsonToObject<T>(userText)` | hard |
| 200/209/532 | Info exposure via error text / log | - | NEW | `Response.Content := E.Message`; `ShowMessage(E.StackTrace)`; log of password var | easy-medium |
| 798/259/321 | Hard-coded credential/password/key (CISQ) | hardcoded-credential, hardcoded-connection-string, dfm-hardcoded-credential | HAVE | `const Pwd='x'` | easy |
| 312/256/313 | Cleartext storage of password | - | NEW | `Ini.WriteString('db','Password',P)`; registry write of a password name | easy |
| 549 | Password field not masked | - | NEW | DFM `TEdit` named *Password* with no `PasswordChar` | easy (DFM) |
| 327/328/326 | Broken/weak hash or cipher, short key | - | NEW | `THashMD5`, `THashSHA1`, `TIdHashMD5` for passwords; DES/RC4 | easy |
| 330/338 | Weak PRNG | weak-random-for-security | HAVE | `Token := Random(...)` | easy |
| 336 | Same seed every run | - | NEW* C #46 | `RandSeed := 42` | easy |
| 295 | Certificate validation off | - | NEW* C #23 | `OnVerifyPeer ... Result := True` | easy-medium |
| 319/311 | Cleartext transmission / no TLS | - | NEW | `'http://...'` in TNetHTTPClient/Indy; `TIdSMTP` with `UseTLS=utNoTLSSupport` | easy |
| 611 | XXE | - | NEW | MSXML `resolveExternals := True`, `ProhibitDTD=False` | easy-medium |
| 427/426 | Untrusted search path (DLL) | - | NEW | `LoadLibrary('foo.dll')` relative name | easy |
| 377 | Insecure temp file | insecure-temp-file | PARTIAL | hardcoded temp only; fixed name under `TPath.GetTempPath` | easy |
| 367 | TOCTOU | stat-gated-destructive | PARTIAL | `if FileExists(F) then TFileStream.Create(F,...)` (C #83) | easy-medium |
| 732 | Incorrect permissions | - | NEW (low) | `CreateFile`/`CreateMutex` with open security attributes | easy |
| 1051 | Hard-coded network resource | hardcoded-ip-address | HAVE | `'192.168.1.5'` | easy |
| 1088 | Remote access without timeout | - | NEW | `TIdHTTP`/`TIdTCPClient` ReadTimeout=0 (Indy default = infinite); `TNetHTTPClient` no timeouts | easy-medium |
| 1052 | Excessive hard-coded literals | magic-literal, large-magic-number | HAVE | | easy |
| 401/772/775/404/1091 | Leak / resource not released | object-leak, unprotected-object-free, dataset-open-without-close, criticalsection-not-released | HAVE | `T := TFoo.Create;` no Free | medium |
| 772/775 | Handle/file leak | - | PARTIAL | `AssignFile` w/o `CloseFile`; `CreateFile` w/o `CloseHandle` | easy-medium |
| 401 | Owned field never freed in Destroy | object-leak (per routine) | PARTIAL (S1 #1) | `FList := TList.Create` in Create | medium |
| 762/590 | Mismatched alloc/free | - | NEW | `GetMem` + `Dispose`; `FreeMem(@Local)`; `Free` on a `GetMem` pointer | medium |
| 457/456/665/908 | Uninitialised variable/resource | used-before-assignment, write-only-local | HAVE | `var N: Integer; Inc(N)` | medium |
| 824/825 | Uninitialised / expired pointer | - | PARTIAL | `P: PChar;  P^ := 'a'` | medium |
| 562/825 | Return address of local | - | NEW | `Result := PChar(LocalStr)`; `Result := @LocalRec` | easy-medium |
| 197/194/195/196/681 | Numeric truncation / sign conversion | nativeint-truncation, win64-pointer-cast, lossy-cast | PARTIAL | `Integer(Int64Val)`; Integer vs Cardinal compare | medium |
| 190/191 | Overflow before widening | - | NEW* S1 #16 | `I64 := A*B` (Integer) | medium |
| 369 | Divide by zero | division-by-zero-literal | PARTIAL | `X div N` with N unchecked | hard |
| 704 | Wrong cast | unsafe-typecast-without-is | HAVE | `TFoo(Sender)` | easy |
| 252/253/391/392 | Unchecked return / error | function-result-ignored (same unit) | PARTIAL | `CloseHandle(H);` `S.Read(B,N);` (S1 #20, C #63) | easy-medium |
| 390/396/397/703 | Empty/generic catch, swallowed | empty-except, empty-on-handler, try-except-swallowed, bare-except, raise-bare-exception | HAVE | | easy |
| 248 | Exception escapes thread/destructor | - | NEW* S1 #9 | `Execute` w/o try/except | easy |
| 667/764/833 | Locking (leak of lock, order) | criticalsection-not-released | PARTIAL | Enter w/o finally HAVE; two locks in opposite order NEW | hard |
| 662/567/820/821/366 | Missing/incorrect synchronisation | ui-access-in-thread, mutable-global-variable | PARTIAL | thread writes a global/field without lock | medium-hard |
| 1058 | Multi-thread use of non-final static | mutable-global-variable | PARTIAL | global var written from Execute | medium |
| 1096/543 | Singleton w/o locking | - | NEW | `if FInst=nil then FInst:=TFoo.Create` in class function, no lock | easy-medium |
| 835/1095 | Infinite loop / loop condition not updated | empty-loop-body (part) | NEW | `while I<N do DoIt;` (I never changed); `while True` no Break/Exit | easy-medium |
| 1082 | Self destruction | - | NEW (low) | `Free;` inside own method (not FreeOnTerminate) | easy |
| 1045/1079/1087 | Child dtor/virtual dtor | destructor-without-override | HAVE | | easy |
| 480/783/570/571 | Wrong operator / precedence / always true-false | not-comparison-precedence, not-in-precedence, constant-condition, comparison-same-operands, uppercase-compare-always-false | HAVE | | easy |
| 561/1041/563/1085/1075 | Dead / redundant / commented-out code, goto | code-after-exit, identical-then-else, redundant-*, overwrite-before-read, commented-out-code, goto-statement | HAVE | | easy |
| 478 | Missing default in multi-branch | exhaustive-enum-case | PARTIAL | non-enum `case` w/o else (C #81) | easy |
| 1047/1074/1086/1064/1080/1048/1090/1054 | CISQ maintainability structure | circular-uses, deep-inheritance, too-many-children, too-many-parameters, unit-too-large, fan-out, feature-envy, layering-violation | HAVE | | easy |
| 1062 | Parent references child | - | NEW (low) | base-class method `if Self is TChild` | easy |
| 1077 | Float compare with wrong operator | float-equality-comparison | HAVE | | easy |
| 407/1046 | Inefficient algorithm / string concat | concat-in-loop | PARTIAL | `Delete(S,1,1)` in loop; `IndexOf` in loop | medium |
| 1049/1050/1060/1073 (?) | CISQ performance: queries in loop | field-by-name-in-loop (only a part) | PARTIAL | `Q.ExecSQL` / `Q.Open` per iteration | medium |
| 758 | Unspecified evaluation order | - | NEW* C #26 | `Format('%d %d',[Next,Next])` | medium |
| 20/129/606 | Input validation: index/loop bound from input | - | NEW | `A[StrToInt(S)]` | hard |

No Delphi analogue or framework-level only (one line): 352 CSRF, 862/863/284/285/287/288/306/639/915 (authn/authz,
app logic), 434 upload, 918 SSRF (taint only), 123/822/823 (write-what-where), 213/359 (privacy policy), 1055 multiple
inheritance, 1066/1070/1097/1098 (serialization/copy-control in C++/Java), 424 alternate path.

## B. SEI CERT C (and C++)

C rule index fetched (families EXP INT MEM ERR CON STR FIO ARR MSC DCL FLP PRE SIG POS ENV; API empty).
C++ index NOT fetched: C++ ids below are from memory "?" (DCL57-CPP, ERR54/61-CPP, EXP50-CPP, CON54-CPP).
Dropped (no Delphi analogue): PRE, SIG, POS, ARR32/36-39, EXP32/35/36/39/42/43/47, INT36, MEM33/36, STR30/37,
FIO32/34/37-41/44, MSC38/39, DCL36-40/42, FLP32/36-38, CON32/34/37/40.

| CERT id | Rule (short) | Our rule | Status | Delphi form | Feas |
|---|---|---|---|---|---|
| EXP30 / EXP50-CPP? | Order of evaluation side effects | - | NEW* C #26 | `Foo(Inc(I), I)` | medium |
| EXP33 | Uninitialised read | used-before-assignment | HAVE | | medium |
| EXP34 | Null deref | not-assigned-interface | PARTIAL | S1 #7, #8 | medium |
| EXP37 | Correct arg count/type | format-argument-count, format-specifier-type-mismatch | HAVE | | easy |
| EXP40 | Modify constant objects | - | NEW | `{$J+}` writable typed const; assign to const param via cast | easy |
| EXP46 | Bitwise op on boolean-like | - | NEW (low) | `{$B+}` complete evaluation; `and` on Boolean with side effects | easy |
| INT30/32 | Overflow | - | NEW* C #48 / S1 #16 | `{$Q-}`, `A*B` widened late | medium |
| INT31 | Lossy conversions | lossy-cast, nativeint-truncation | PARTIAL | Int64 -> Integer, Integer -> Word | medium |
| INT33 | Div by zero | division-by-zero-literal | PARTIAL | unchecked divisor | hard |
| INT34 | Bad shift count | - | NEW* C #13 | `1 shl 40` | medium |
| MEM30 | Access freed memory | use-after-free | HAVE | | medium |
| MEM31 | Free when done | object-leak | HAVE | | medium |
| MEM34 | Free only allocated | - | NEW | `FreeMem(@Local)`, mismatched pair | medium |
| MEM35 | Allocate sufficient memory | - | NEW | `GetMem(P, SizeOf(Pointer))` for a record | medium |
| MEM01-C? | Null pointer after free | use-after-free | PARTIAL | field `.Free` without nil (C #31) | easy-medium |
| ERR33 | Detect library errors | function-result-ignored | PARTIAL | S1 #20 | easy-medium |
| ERR34 | Detect string-to-number errors | - | NEW | bare `StrToInt(Edit.Text)` outside try; use TryStrToInt | easy |
| ERR54-CPP? | Handler order | duplicate-exception-handler | PARTIAL | ancestor before descendant (C #70) | easy-medium |
| ERR61-CPP? | Catch by ref, do not own | - | NEW* C #16 | `E.Free` in handler | easy |
| DCL57-CPP? | No exception out of dtor | - | NEW* C #10 | | easy |
| CON33 | Thread-unsafe library calls | - | NEW | global `FormatSettings` / `DecimalSeparator` / shared `TList` in thread | medium |
| CON35 | Lock in predefined order | - | NEW | A.Enter;B.Enter vs B.Enter;A.Enter | hard |
| CON36/41, CON54-CPP? | Wait in a loop | - | NEW* C #56 | `TMonitor.Wait` in `if` | easy |
| CON39 | Do not join/detach twice | - | NEW | `FreeOnTerminate:=True` then `.WaitFor`/`.Free` (use after free) | medium |
| CON43 | Data races | ui-access-in-thread, mutable-global-variable | PARTIAL | | hard |
| CON31 | Do not destroy a locked mutex | criticalsection-not-released | PARTIAL | `FCS.Free` while held | hard |
| STR31 / ARR38 | Sufficient space / library bounds | unsafe-string-api | PARTIAL | `Move` size; PChar buffers | medium |
| STR32 | Null termination | unsafe-string-api | PARTIAL | `SetString`/`Move` into PChar w/o #0 | hard |
| STR34/38 | Narrow/wide confusion | lossy-cast | PARTIAL | `PAnsiChar(S)`, `Length(S)` as byte count (S1 #2) | medium |
| FIO30/47 | Format string | format-argument-count | NEW* C #24 | | easy |
| FIO42 | Close files | object-leak (streams) | PARTIAL | `AssignFile` w/o `CloseFile` | easy |
| FIO45 | TOCTOU | stat-gated-destructive | PARTIAL | C #83 | easy-medium |
| FIO46 | Access closed file | use-after-free | PARTIAL | `CloseFile(F); Read(F,..)`, `CloseHandle(H)` then use | medium |
| MSC30 | rand | weak-random-for-security | HAVE | | easy |
| MSC32 | Seeding | - | NEW* C #46 | | easy |
| MSC37 | Control reaches end of non-void | function-result-not-set | HAVE | | medium |
| MSC41 | No hard-coded sensitive info | hardcoded-credential | HAVE | | easy |
| DCL30 | Storage duration (address of local escapes) | - | NEW | `Result := @Local`, `PChar(LocalStr)` | easy-medium |
| FLP30 | Float loop counter | - | NEW* C #34 | | easy-medium |
| ENV32 | Exit handlers return normally | - | NEW* C #59 | `Halt` in library unit | easy |
| ENV33 | Do not call system() | unsafe-shellexecute | PARTIAL | `WinExec`/`ShellExecute` with literal command are allowed by us | easy |

## C. MISRA C:2012 / C++:2023 themes (headlines only, from memory ?)

MISRA C:2012 groups: Directives 1-4, Rules 1-22 (about 175 guidelines). C++:2023 (about 179 rules) merges
MISRA C++:2008 and AUTOSAR C++14 themes. Rule text is paywalled; mapping is by theme.

| Theme (MISRA ?) | Delphi translation | Ours | Status |
|---|---|---|---|
| R2 unused code (2.1 unreachable, 2.2 dead, 2.3-2.7 unused type/label/param) | unused-local/param/private/unit, code-after-exit | many | HAVE |
| D4.4 commented-out code | commented-out-code | yes | HAVE |
| R3 comments (3.1 nested comment markers) | `{` inside `(* *)`, `//` inside `{ }` | - | NEW (easy, low) |
| R5.3 identifier shadowing | local/param shadows field or outer symbol | with-hides-outer-symbol (with only) | NEW (easy-medium) |
| R8.9 / R8.7 narrow scope | global var used by one routine -> local; interface symbol used only in its unit | mutable-global-variable, S1 #18/#19 | PARTIAL |
| R9 initialisation | used-before-assignment | yes | HAVE |
| R10 essential type model (mixed signedness, narrowing, float/int) | Integer/Cardinal mixes, Int64->Integer | lossy-cast | PARTIAL |
| R12.1 precedence, 12.2 shifts | mixed and/or, `not A = B`, shl count | not-*-precedence | PARTIAL (C #39, #13) |
| R13 side effects (13.2 order) | evaluation order unspecified | - | NEW* |
| R14 control flow (14.1 float counter, 14.3 invariant cond) | | constant-condition | PARTIAL |
| R15 (15.1 goto, 15.5 single exit, 15.6 braces, 15.7 else-if ends with else) | | goto-statement, too-many-exit-points | PARTIAL (C #41; else-if-without-else NEW low) |
| R16 switch (16.4 default) | case without else | exhaustive-enum-case | PARTIAL (C #81) |
| R17 functions (17.2 recursion, 17.7 result used, 17.8 param not modified) | | - | NEW* C #33, #63, #44 |
| D4.12 / R21.3 no dynamic memory | n/a for Delphi; "no GetMem" profile only | - | skip |
| R21.8 no abort/exit | Halt in library unit | - | NEW* C #59 |
| R22 resources (22.1 released, 22.2 only free allocated, 22.6 no use of closed) | | object-leak, use-after-free | PARTIAL (MEM34 NEW) |
| D4.7 / D4.11 error info checked, values validated | return codes | function-result-ignored | PARTIAL |
| D4.5 typographically unambiguous identifiers | confusable-identifier | underscores only | PARTIAL (`l/1`, `O/0`, case-only: NEW low) |
| R1 / R19 / R20 (extensions, overlapping, preprocessor) | `$IFDEF` hygiene, variant records, absolute | ifdef-undefined-symbol | PARTIAL (variant punning FILED) |
| C++:2023: no throw in dtor, RAII, const-correctness, no unions, explicit conversions | dtor exceptions, try/finally + interfaces, const params | | PARTIAL (dtor NEW*, const params NEW) |

Recommendation: ship a `safety` (MISRA-ish) PROFILE (config only) over existing rules plus the S1/C-survey items
17.2 recursion, 17.8, 5.3 shadowing, 15.6, 16.4, 21.8, 13.2, and the {$Q-}/{$R-} directive rule. No new engine work beyond those rules.

## D. Rust Clippy (841 lints; groups correctness=deny, suspicious/complexity/perf/style=warn, pedantic/restriction/nursery/cargo=allow)

Fetched: group names and a few lint names only (first 100k of 626k chars). Lint names not marked "(fetched)" are from memory ?.
Excluded: borrow/lifetime/iterator/Option/Result lints (no Delphi analogue) and anything in the earlier surveys.

| Clippy lint ? | Group | Delphi form | Ours | Status | Feas |
|---|---|---|---|---|---|
| absurd_extreme_comparisons (fetched) | correctness | `Byte < 0`, `Cardinal >= 0`, `Word > 65535` always false/true | constant-condition (literals only) | NEW | easy-medium |
| bad_bit_mask / ineffective_bit_mask (fetched) | correctness | `(X and 1) = 2`, `(X or 1) <> 0` | - | NEW | easy |
| approx_constant (fetched) | correctness | `3.14159` instead of `Pi` | magic-literal (generic) | NEW | easy |
| out_of_bounds_indexing | correctness | `A[10]` on `array[0..9]` | - | NEW | easy |
| almost_swapped (fetched) | correctness | `A := B; B := A;` | self-assignment | NEW | easy |
| erasing_op / identity_op | correctness/complexity | `X*0`, `X and 0`, `X+0`, `X*1`, `X shl 0` | - | NEW | easy |
| invalid_regex | correctness | `TRegEx.Create('(')` with literal pattern | - | NEW | medium (regex parse) |
| while_immutable_condition / maybe_infinite_iter | correctness | `while I<N do` no change to I | - | NEW | easy-medium |
| eq_op, ifs_same_cond, never_loop | correctness | | comparison-same-operands, repeated-else-if-condition, loop-executes-at-most-once | HAVE | |
| await_holding_lock (fetched) | suspicious | blocking call under lock: `Synchronize`, `Sleep`, `WaitFor`, `ShowMessage` between Enter..Leave | criticalsection-not-released (leak only) | NEW | medium |
| suspicious_else_formatting | suspicious | `else` then `if` on next line indented as sibling; dangling else | - | NEW (low) | easy |
| misrefactored_assign_op | suspicious | `A := A + B + A` style typo | - | NEW (low) | easy |
| suspicious_xor_used_as_pow | restriction | `2 xor 8` | - | NEW (low) | easy |
| nonminimal_bool | complexity | `not (A = B)` -> `A <> B`; `not (A and not B)` | redundant-not-not | NEW | easy |
| collapsible_if / collapsible_else_if (fetched) | style/pedantic | `if A then if B then`; `else begin if ... end` | - | NEW | easy |
| needless_return | style | `Exit;` as last statement; `Exit(Result)` at end | - | NEW | easy |
| redundant_else | pedantic | `else` after `Exit`/`raise` | - | NEW | easy |
| int_plus_one | complexity | `X >= Y+1` -> `X > Y` | - | NEW (low) | easy |
| manual_range_contains | style | `(X>=A) and (X<=B)` -> `InRange` | - | NEW (low) | easy |
| explicit_counter_loop | complexity | manual `Inc(I)` counter inside `for` | - | NEW (low) | easy |
| match_same_arms | pedantic | two `case` branches with identical body | identical-then-else (if only) | NEW | easy |
| if_not_else | pedantic | `if not X then A else B` | - | NEW (low) | easy |
| unused_self | pedantic | method never touches Self/fields -> class method | unused-parameter | NEW | medium |
| shadow_same / shadow_unrelated / shadow_reuse | restriction | local or param re-declares a field/outer name | with-hides-outer-symbol | NEW | easy-medium |
| needless_pass_by_value / large_types_passed_by_value | pedantic/perf | string/record/array value param never modified -> `const` | - | NEW | easy-medium |
| large_stack_arrays | pedantic | local `array[0..1048575]` | - | NEW | easy |
| cast_possible_truncation (fetched) | pedantic | Int64->Integer, Integer->Byte | lossy-cast (strings), nativeint-truncation | PARTIAL | medium |
| cast_sign_loss / cast_possible_wrap (fetched) | pedantic | Integer <-> Cardinal/UInt64 | - | NEW | medium |
| cast_precision_loss | pedantic | Int64 -> Double/Single | - | NEW (low) | medium |
| assertions_on_constants (fetched) | style | `Assert(True)` | assert-call (message only) | NEW (low) | easy |
| float_cmp, len_zero, bool_comparison, needless_bool, too_many_arguments, too_many_lines, cognitive_complexity, many_single_char_names | various | | float-equality-comparison, length-zero-compare, boolean-comparison-true, boolean-result-returned-directly, too-many-parameters, method-too-long, cognitive-complexity, hungarian-or-short-identifier | HAVE | |
| missing_errors_doc / missing_panics_doc | pedantic | routine that raises but its DocInsight has no `<exception>`; extends doc-drift | doc-drift, missing-doc | NEW | easy-medium |
| todo / unimplemented / panic | restriction | `raise Exception.Create('Not implemented')`, `Abort` stub, `Halt` | compiler-magic-comments (comments only) | NEW | easy |
| dbg_macro / print_stdout / missing_assert_message | restriction | | outputdebugstring, writeln-in-source, assert-call | HAVE | |
| mutex_integer / mutex_atomic | nursery/restriction | critical section around one Integer -> TInterlocked | - | NEW (low) | medium |
| arithmetic_side_effects / indexing_slicing | restriction | `{$Q-}` / unchecked index | - | NEW* C #48 | easy |

## E. DerScanner

Public pages (derscanner.com home, search summaries): "Delphi Security" product = SAST + SCA + SBOM + code quality
"for Delphi and Object Pascal", native Delphi parser, 43 languages, findings mapped to CWE, OWASP Top 10, SANS/CWE Top 25,
PCI DSS/HIPAA reports; MITRE CWE-compatible (vendor claim); SCA for RAD Studio components released 2026-01.
NOT public: the Delphi rule list (docs.derscanner.com not reached; derscanner.com/delphi returned 404).
One Delphi forum anecdote reports thin Delphi depth and false positives (single source, unverified).
Take-away: the only visible commitments are CWE mapping, injection/credential/insecure-pattern classes, SBOM/SCA.
CWE ids on findings is the expected enterprise report format; SBOM/SCA is an area drag-lint lacks.

## F. Recommendation: tag rules with CWE ids

Yes. It is metadata only (no EXTRACTOR_VERSION bump), helps audits, and enables `--profile cwe-top25`.
Design:
* Add `cwe: [id, ...]` (first = primary best fit) to each rule's metadata; show it in `rules --json` and `lint --json`.
* SARIF 2.1.0 (from memory ?): `run.taxonomies[]` with a toolComponent named "CWE" (version, organization MITRE,
  `taxa[]`); each rule `reportingDescriptor` gets `relationships[]` -> `{target:{id:"89", toolComponent:{name:"CWE"}}, kinds:["relevant"]}`;
  also `properties.tags: ["external/cwe/cwe-89"]` which GitHub code scanning reads, plus `security-severity` on security rules.
* Others (?): SonarQube rule metadata carries CWE/OWASP security standards; Cppcheck prints `cwe="n"` in XML and has a `{cwe}` template
  field; clang-tidy exposes CERT aliases (`cert-*`) not CWE ids; PVS-Studio puts CWE and CERT/MISRA ids on its rule pages.
* Use Base/Variant ids where possible; avoid ids MITRE marks discouraged for mapping (396/397 are generic: prefer 390/703) (?).
  Review each mapping by hand; do not auto-generate.
* Do not tag naming, documentation, review-marker, parser rules; metrics/complexity only with CISQ maintainability ids.

Proposed map rule id -> CWE (primary; secondary in brackets). From titles; "?" = weaker fit:

| rule id | CWE |
|---|---|
| sql-injection-concat | 89 |
| path-traversal | 22 [23, 36] |
| unsafe-shellexecute | 78 [77, 88] |
| hardcoded-credential | 798 [259] |
| hardcoded-connection-string | 798 [259] |
| dfm-hardcoded-credential | 798 [259] |
| hardcoded-ip-address | 1051 |
| hardcoded-absolute-path | none (426 ? weak) |
| insecure-temp-file | 377 |
| weak-random-for-security | 338 [330] |
| use-after-free | 416 |
| interface-object-mixing | 415 [416] |
| double-free | 415 |
| object-leak | 401 [772] |
| unprotected-object-free | 772 [404] |
| dataset-open-without-close | 772 [404] |
| criticalsection-not-released | 667 [772] |
| interface-reference-cycle | 401 |
| freeandnil-on-interface | 762 ? |
| used-before-assignment | 457 |
| out-param-not-set | 457 ? |
| function-result-not-set | 457 [394 ?] |
| not-assigned-interface | 476 |
| unsafe-typecast-without-is | 704 |
| division-by-zero-literal | 369 |
| lossy-cast | 197 [704] |
| nativeint-truncation | 197 |
| win64-pointer-cast | 197 |
| unsafe-string-api | 120 [676 ?] |
| pchar-arithmetic | 468 ? [119] |
| off-by-one-count | 193 |
| format-argument-count | 685 |
| format-specifier-type-mismatch | 686 |
| float-equality-comparison | 1077 |
| gettickcount-wraparound | 190 |
| empty-except, empty-on-handler, try-except-swallowed, exception-constructed-but-not-raised | 390 [391 ?] |
| bare-except, raise-bare-exception | 396 ? / 397 ? (prefer 703) |
| control-flow-in-finally, raise-in-finally | 584 |
| stat-gated-destructive | 367 |
| ui-access-in-thread | 567 [820] |
| mutable-global-variable | 1058 ? [567] |
| code-after-exit, loop-executes-at-most-once, repeated-else-if-condition | 561 |
| constant-condition, comparison-same-operands, uppercase-compare-always-false | 570 [571] |
| identical-then-else, redundant-cast, redundant-not-not, boolean-comparison-true, boolean-result-returned-directly, duplicate-code | 1041 |
| write-only-local, overwrite-before-read, self-assignment | 563 |
| not-comparison-precedence, not-in-precedence | 783 |
| exhaustive-enum-case, empty-case-branch | 478 ? |
| goto-statement | 1075 |
| commented-out-code | 1085 |
| circular-uses | 1047 |
| deep-inheritance | 1074 |
| too-many-children | 1086 |
| too-many-parameters | 1064 |
| unit-too-large | 1080 |
| fan-out, high-coupling | 1048 ? |
| feature-envy | 1090 |
| magic-literal, large-magic-number, case-magic-numbers | 1052 ? |
| destructor-without-override, missing-inherited-dtor | 1045 [1079, 1087] |
| concat-in-loop | 1046 ? [407] |

About 70 of 195 rules get a CWE; the rest are intentionally untagged (naming, docs, review markers, refactoring signals).

## Sources
* https://cwe.mitre.org/top25/archive/2025/2025_cwe_top25.html (fetched)
* https://cwe.mitre.org/data/definitions/1305.html (fetched, partial: first 100k chars)
* https://cwe.mitre.org/data/definitions/1340.html (fetched)
* https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/ (fetched; moved from wiki.sei.cmu.edu)
* https://clippy.rust-lang.org/master/index.html (fetched, partial)
* https://derscanner.com/ (fetched); https://en.wikipedia.org/wiki/DerScanner ; https://lp.embarcadero.com/ImproveQualityandSecurity ; https://forums.adug.org.au/t/aikido-dev-security-scanning-for-delphi-apps/61325 (search results only)
* Not fetched (memory ?): SARIF 2.1.0 taxonomy sections; MISRA C:2012 / C++:2023 headlines; CERT C++ ids; Sonar/Cppcheck/clang-tidy CWE exposure.
* Earlier surveys: docs/lint/SURVEY-2026-10-27-rule-gaps.md, docs/lint/SURVEY-2026-10-27-c-cpp-linters.md.
