; A broken hash or cipher used in a routine that handles a secret (CWE-328, CWE-327).
; MD5 / SHA-1 / DES / RC4 and SSLv2/3 are not safe for passwords, tokens, signatures or
; credentials. Scoped, like weak-random-for-security, by the ROUTINE name: the identifier
; must sit inside a defProc whose name matches pass|pwd|secret|token|cred|auth|login|sign.
; THashMD5 inside FileChecksum is an integrity checksum, not a secret, and stays silent.
; #in? is drag-lint's own predicate (see rules\README.md): an ancestor of the given node
; type whose name: field matches the regex.
((identifier) @warn
  (#any-of? @warn "THashMD5" "THashSHA1" "TIdHashMD5" "TIdHashSHA1" "TIdHashMessageDigest5" "TDCP_md5" "TDCP_sha1" "TDCP_des" "TDCP_rc4" "sslvSSLv2" "sslvSSLv3")
  (#in? @warn "defProc" "(?i)(pass|pwd|secret|token|cred|auth|login|sign)"))
