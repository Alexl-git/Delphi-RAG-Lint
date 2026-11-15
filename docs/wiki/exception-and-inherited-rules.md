# Exception and inherited lint rules

Rules about exception handlers and `inherited` calls. They walk the syntax tree
per unit in `lint` and `lint-all`; ancestor questions (does a base class declare
this method?) use the project index plus the platform library index.

| Rule | Default | Severity | Fires on |
|---|---|---|---|
| `except-handler-order` | ON | warning | an `on E: T do` handler that an earlier handler for an ancestor type already catches |
| `exception-freed` | ON | warning | `E.Free` inside the handler that received `E`: the RTL frees it |
| `inherited-wrong-method` | ON | warning | an override that calls `inherited` of a different method |
| `message-handler-without-inherited` | ON | warning | a `message` handler with neither `inherited` nor `DefaultHandler` |
| `inherited-without-ancestor` | ON | warning | a bare `inherited` in a method that no ancestor declares |
| `override-only-inherited` | ON | hint | an override whose body is only `inherited` |
| `destroy-called-directly` | ON | warning | `X.Destroy` instead of `X.Free` |
| `missing-inherited-call` | ON | warning | `Loaded`, `CreateParams` and similar component hooks overridden without `inherited` |
| `inherited-order` | OFF | warning | a destructor that calls `inherited` before freeing its own members |

`inherited-order` is OFF by default: over the four sample projects 4 of its 5
findings were `TThread` descendants, where `inherited Destroy` must run first
because it waits for `Execute`. Enable it with `--rule inherited-order` or the
config key `"enabled"`. It stays OFF until classes with a `TThread` ancestor are exempted.

The other eight rules produced no findings over the same projects.