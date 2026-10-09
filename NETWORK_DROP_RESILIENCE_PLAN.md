# DICOMKit — Network Drop Resilience Plan

**Scope:** `DICOMNetwork` (association read path, error taxonomy, retry layer), `dicom-query` CLI, `DICOMStudio` query view model.
**Date:** 2026-09-17
**Status:** Planned — nothing applied yet.

**Trigger scenario:** A C-FIND query is issued to a PACS. The PACS accepts the association and receives the request. The network then drops mid-response. The caller gets no results, an unhelpful error, or — in the silent-drop case — an indefinite hang.

**Tally:** 1 critical · 3 high · 2 medium · 3 low/hardening.

> Line numbers are from the current working tree at the date above. Every claim below was confirmed by reading the surrounding code.

---

## Root cause summary

The `timeout` parameter passed to every query API is a **connect-phase timeout only**. It races the TCP handshake at `DICOMConnection.swift:375-396` and is never consulted again once the connection is established.

The DICOM ARTIM timer (default 30s, `Association.swift:95`) is correctly implemented in `receiveWithARTIMTimer` (`Association.swift:622`) but is called from exactly two places: `request(...)` (`:377`) and `release()` (`:539`). It does **not** guard the data-transfer path.

```
[ connect ]──[ send query ]──[ receive results ]──[ release ]
     ▲                              ▲                  ▲
 timeout:60                    UNPROTECTED         ARTIM:30
 ARTIM:30                       ← the gap →
```

Both timers guard the edges of the association. Neither guards the middle — the phase that runs longest and streams the most data.

`Association.receive()` (`Association.swift:487`) calls `conn.receivePDU()` raw. Underneath, `DICOMConnection.receive(length:)` (`:595`) posts an `NWConnection.receive` with no deadline. The source already documents the consequence at `DICOMConnection.swift:603-606`:

> `NWConnection.receive` has no read deadline, and its completion handler never fires if the peer holds the socket open while sending nothing … There is no ARTIM/timeout wrapper on DIMSE-response reads.

### Behaviour by failure mode

| How the network dies | Detected? | Outcome |
|---|---|---|
| Before/during connect | Yes — `timeout` applies | Clean `.timeout` |
| After connect, polite close (FIN) | Yes — `isComplete` | `.connectionClosed`, results lost |
| After connect, reset (RST) | Yes — transport error | `.connectionFailed`, results lost |
| After connect, **silent** (cable pull, Wi-Fi off, VPN drop, NAT timeout) | **No** | **Hangs indefinitely** |

The silent case has no application timer and no TCP keepalive (`DICOMConnection.swift:285-290`, `:322-328` set no TCP options), so nothing detects it.

---

## Findings and planned fixes

### C1 — Unbounded DIMSE response read (critical)

**Files:** `Sources/DICOMNetwork/Association.swift:478-513`

`Association.receive()` calls `conn.receivePDU()` with no deadline. On a silent peer disappearance the read never resumes and the operation blocks forever.

**Affected callers — seven services, all calling `association.receive()` raw:**

| Service | Receive loop |
|---|---|
| `QueryService.swift` | `:580` |
| `StorageService.swift` | `:946` |
| `RetrieveService.swift` | `:875`, `:1072` |
| `StorageCommitmentService.swift` | `:746` |
| `ModalityWorklistService.swift` | `:642` |
| `VerificationService.swift` | `:502` |
| `DICOMStorageClient.swift` | `:929` |

`PrintService` is the sole exception — it routes through `receiveWithTimeout` (`PrintService.swift:3648-3690`), whose doc comment names this exact bug.

**Fix.** Generalize the `PrintService.receiveWithTimeout` pattern into `Association.receive()` so all seven services are covered by one change.

The pattern has **two** halves and both are required:

1. Race the receive against a deadline.
2. On expiry, call `try? await association.abort()` to force the blocked read to unwind.

Half 2 is not optional. `receiveWithARTIMTimer` performs only half 1, and racing a `Task.sleep` alone does not resume the orphaned `NWConnection.receive` continuation. `PrintService` gets this right at `:3665`; it also disambiguates a failure surfacing at the deadline, re-reporting it as the timeout rather than the secondary abort error (`:3680-3687`).

**Resulting behaviour:** indefinite hang → `.operationTimeout` (or `.artimTimerExpired`) after the configured bound, across all seven services.

---

### C1a — Fire the transport-closed event (high, same code path as C1)

**Files:** `Sources/DICOMNetwork/Association.swift:487`

`Association.receive()` propagates the throw with no `catch`, so it never dispatches `.transportConnectionClosed` and never calls `conn.abort()`. `AssociationStateMachine` is a pure transition table with no timers — it only moves when fed an event.

The needed transition already exists and is correct (`AssociationStateMachine.swift:360-365`):

```swift
case (.established, .transportConnectionClosed):
    // AA-4: Transport connection closed
    return TransitionResult(newState: .idle,
        actions: [.issueAbortIndication(.serviceProvider, AbortReason.notSpecified.rawValue)])
```

Nothing dispatches it. The association remains `.established` describing a dead socket; the next `send`/`receive` passes the `guard state == .established` check and fails deeper with `.invalidState("Cannot receive: connection not established")`, masking the real cause.

**Fix.** Add a `catch` on the association read path that fires `.transportConnectionClosed`, calls `conn.abort()`, and clears `connection`/`negotiated` before rethrowing.

**Latent today** (each query builds a fresh association, so the stuck one is discarded) but becomes live as soon as retry (H2) or connection reuse is enabled.

**Also note:** `.abortSent` is declared at `AssociationStateMachine.swift:111` but matches no `case` pattern — it falls to `default` and returns unchanged state. Harmless today because the following `.transportConnectionClosed` corrects it. Fix opportunistically while in this file.

---

### H1 — Truncated read mis-typed as a protocol error (high)

**Files:** `Sources/DICOMNetwork/DICOMConnection.swift:640-645`, `Sources/DICOMNetwork/DICOMNetworkError.swift:629`

Because `receive(length:)` sets `minimumIncompleteLength == maximumLength == length`, a short-but-non-terminal delivery falls to the final `else` and throws:

```swift
DICOMNetworkError.decodingFailed("Incomplete data received")
```

That is categorized `.protocol` with `isRetryable == false`. A transient network truncation is therefore reported to callers as a **permanent protocol violation**.

**Fix.** Map that branch to a transient case — either `.connectionClosed` or a new dedicated truncation case — so `category` returns `.transient` and `isRetryable` returns `true`.

**Ordering constraint:** this is a hard prerequisite for H2. Enabling retry while H1 stands means retry silently refuses to fire on exactly the case it is meant to survive, and it will present as "the retry config didn't take effect."

---

### H2 — Retry layer bypassed and disabled (high)

Three independent defects in the recovery layer. None touch the transport.

**(a) Two public front doors.** `DICOMClient.findStudies` forwards to the static `DICOMQueryService.findStudies` (`DICOMClient.swift:657`). Both are public entry points; only the former passes through `withRetry`. The `dicom-query` CLI (`QueryExecutor.swift:19`) and the app (`CLIWorkshopViewModel.swift:7914`) both call the static one, bypassing the resilience layer entirely.

**(b) Disabled by default.** All five `DICOMClient` initializers default to `retryPolicy: .noRetry` and `circuitBreakerConfiguration: nil` (`DICOMClient.swift:273`, `:317`, `:360`, `:403`, `:589`). `.noRetry` sets `maxAttempts: 0`, so `withRetry` loops `0...0` and rethrows on the first failure.

**(c) Two classifiers that disagree.** Opposite fallbacks for non-`DICOMNetworkError` types:

| Classifier | Non-`DICOMNetworkError` | Line |
|---|---|---|
| `RetryPolicy.shouldRetry` | `false` | `RetryPolicy.swift:184` |
| `DICOMClient.shouldRetry` | `true` | `DICOMClient.swift:1076` |

They also split on real DICOM cases: `.associationAborted` and `.partialFailure` are `.transient` (retryable by category) but explicitly refused by `DICOMClient` (`:1097`, `:1104`).

**(d) Backoff off-by-one.** `withRetry` computes `policy.delay(forAttempt: attempt)` with `attempt >= 1` (`DICOMClient.swift:996-1000`), while `RetryExecutor` correctly uses `delay(forAttempt: attemptNumber - 1)` (`RetryPolicy.swift:617`). The doc states `0 = first retry` (`RetryPolicy.swift:165`). Delays run **2s/4s/8s instead of 1s/2s/4s**.

**Fix.** Route the static query entry points through the retry layer (or document them as unguarded), choose a sane non-`.noRetry` default for query operations, consolidate the two classifiers into one, and correct the off-by-one.

**Open decision — retry granularity.** The retry unit is `performFind`, which builds a fresh `Association` per call (`QueryService.swift:489`). A drop at result 9,000 of 10,000 replays the **entire** query. This is correct (C-FIND is idempotent, no duplicates) but expensive. There is no C-FIND-CANCEL, resume, or continuation-marker support anywhere in `QueryService`. Combined with `maxTotalTime: nil` (unbounded by default), an enabled policy can replay four full queries with no global deadline. Recommend setting a `maxTotalTime` when enabling.

**Also note:** the circuit breaker, when enabled, is checked once *outside* the retry loop (`DICOMClient.swift:980` vs the `for` at `:995`), so all attempts of one call proceed even if early attempts trip it; it only gates the *next* call.

---

### M1 — Partial results discarded (medium)

**Files:** `Sources/DICOMNetwork/QueryService.swift:576-609`

`results` is a local array in `performCFind`. Any throw from `association.receive()` unwinds the function and discards everything already collected. If the PACS streamed 400 of 500 studies before the drop, the caller gets **zero**, not 400.

**Fix — two options, needs a decision:**

1. **Typed error carrying partials** — add an associated value so callers can recover what arrived. Smaller change, backward-compatible for callers that ignore it.
2. **Streaming variant** — expose `AsyncThrowingStream<GenericQueryResult>` so results are delivered as they arrive and a mid-stream failure leaves prior results already consumed. Better long-term shape; larger public API change.

Recommend option 2 as an *additional* API rather than a replacement, keeping the array-returning form for existing callers.

Note this compounds with H2: today the partials are lost; with retry enabled they are lost *and* re-fetched.

---

### M2 — No TCP keepalive on the client transport (medium)

**Files:** `Sources/DICOMNetwork/DICOMConnection.swift:285-290`, `:322-328`

The client builds `NWParameters.tcp` / `NWParameters(tls:tcp:)` with default `NWProtocolTCP.Options()` and sets no options — a grep for `enableKeepalive`, `keepaliveIdle`, and `connectionTimeout` in this file returns nothing.

By contrast the SCP-side listeners do configure TCP options (`StorageSCP.swift:499`, `PrintSCP.swift:153`, `StorageCommitmentSCP.swift:312`), and `DICOMStudio/Services/NetworkUtilityService.swift:250-251` sets `connectionTimeout`.

**Fix.** Set `enableKeepalive` and a sensible `keepaliveIdle` on the client transport so the kernel can detect a half-open connection independently of the application timer.

**Defense in depth only** — largely redundant once C1 lands, which is why it sits below the retry work.

---

### L1 — Error messages never surfaced to users (low)

The taxonomy already carries good text. `.connectionClosed` is categorized `.transient` (`DICOMNetworkError.swift:558`) with recovery `.retry` (`:680`) and this `userMessage` (`:752`):

> "The network connection was closed unexpectedly by the remote server or due to a network issue."

Neither front end reads it:

- **CLI** — `Sources/dicom-query/QueryExecutor.swift` has no `catch` at all; the error escapes to ArgumentParser and prints a raw enum dump.
- **App** — `CLIWorkshopViewModel.swift:7927-7929` uses `String(describing: error)`.

**Fix.** Catch `DICOMNetworkError` in both and render `userMessage` plus `recoverySuggestion`, keeping the raw value behind a verbose flag.

---

### L2 — `TimeoutConfiguration.read`/`.write` are never applied (low)

**Files:** `Sources/DICOMNetwork/DICOMNetworkError.swift:193-214`

`TimeoutConfiguration` defines `connect`/`read`/`write`/`operation`/`association` with defaults 30/30/30/120/30. Its only reference outside its own file is a computed property at `DICOMClient.swift:91-100`. **Nothing reads `.read` or `.write` to bound any I/O.**

The API advertises per-phase timeouts the transport does not implement — actively misleading for anyone tuning timeouts to fix this class of bug.

**Fix.** Either wire `.read`/`.write` into the C1 timeout, or mark them unimplemented. Preferably the former, using them as the source for C1's bound.

---

### L3 — `MessageAssembler` unbounded and never reset on error (low/hardening)

**Files:** `Sources/DICOMNetwork/MessageAssembler.swift:50-95`

`addPDV` appends into `commandBuffer`/`dataSetBuffer` with no maximum total size and no fragment count limit — a peer streaming `isLastFragment == false` indefinitely grows these without bound. `reset()` (`:34-43`) is never called from any error path.

Memory growth under a misbehaving peer, not a hang. The PDU decode loops themselves are properly bounded with a 128 MB cap (`PDUDecoder.swift:14`, enforced `:49-52`, `:96-99`), so there is no infinite-loop risk.

**Fix.** Add a total-size cap and a fragment-count limit; reset on the error path.

---

## Test plan

No existing test drives a mid-C-FIND drop. `DICOMNetworkErrorTests.swift` tests the enum in isolation; nothing drives a truncated response stream through `performCFind`. The hang case is therefore **untested and undetectable in CI** today.

Add a mock SCP that accepts the association, sends N pending C-FIND-RSPs, then fails in three distinct ways:

| Test | Mock behaviour | Assertion |
|---|---|---|
| `testCFindPeerClosesMidStream` | Close socket (FIN) after 3 of 10 responses | Throws `.connectionClosed`; categorized `.transient`; `isRetryable == true` |
| `testCFindPeerResetsMidStream` | RST after 3 of 10 | Throws `.connectionFailed`; categorized `.transient` |
| `testCFindPeerGoesSilentMidStream` | Accept, send 3, then **never write again, hold socket open** | **Terminates within the ARTIM bound** — this is the C1 regression guard |
| `testCFindTruncatedReadIsRetryable` | Short delivery mid-PDU | Not `.decodingFailed`; `isRetryable == true` (H1 guard) |
| `testCFindPartialResultsPreserved` | Close after 3 of 10 | Caller can recover the 3 (M1 guard) |

The silent test is the important one — it is the only thing that proves C1 works and stops it regressing. It must assert *termination*, with a test-level deadline comfortably above the ARTIM bound so a regression fails rather than hangs CI.

---

## Sequencing

**Batch 1 — C1 + C1a + H1 (one change).** All three live in the same error handler on the association read path: the timeout wrapper, the state-machine event, and the error re-classification. Splitting them means touching the same code three times. H1 also gates H2, so it must land first. Ship with the FIN/RST/silent tests.

**Batch 2 — H2.** Independent; can land any time after H1. Self-contained in the retry layer.

**Batch 3 — M1, M2, L1, L2, L3.** Real value, no urgency. M1 carries a public API decision (see above) and should be agreed before implementation.

### Priority if only one item is done

**C1.** It converts an indefinite hang into a clean, categorized error across seven services, and the correct implementation already exists in `PrintService.receiveWithTimeout`.

---

## Risks and compatibility

- **C1 changes timeout behaviour for all seven services.** Long-running C-MOVE/C-GET retrieves against slow archives could newly time out if the bound is too tight. Mitigation: derive the bound from `TimeoutConfiguration.operation` (default 120s) rather than `.read` (30s) for retrieve paths, and make it configurable per service.
- **C1a changes post-failure association state** from `.established` to `.idle`. Callers inspecting `association.state` after a caught error will observe a different value. No production caller does this today.
- **H1 changes an error case** callers may be matching on. `.decodingFailed` for truncation becomes a transient case — a source-compatible change for exhaustive switches over `DICOMNetworkError`, but a behavioural one for code branching on `isRetryable`.
- **H2's default change** means queries that previously failed once will now retry, increasing worst-case latency. Pair with an explicit `maxTotalTime`.
- **M1 option 2** adds public API surface; it does not remove any.
