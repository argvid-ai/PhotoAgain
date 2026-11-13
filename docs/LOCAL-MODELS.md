# Optional local check-region hints

`PhotoAgainOllama` is an optional developer adapter for a user-controlled Ollama runtime. Native analysis and policy have no dependency on it or networking. The CLI links the adapter, but only `group-hints` contacts a runtime. This slice has been exercised with generated images and an injected mock transport; **no real model inference has been tested**. No model is recommended or claimed compatible based on those tests.

## Explicit opt-in

You must understand and configure the third-party runtime yourself. Passing `--acknowledge-runtime user-confirmed` confirms that choice; it does **not** certify offline operation. Loopback addressing cannot establish whether the receiving process forwards data, logs prompts/images, or contacts cloud services. Ollama documents `OLLAMA_NO_CLOUD=1` or `disable_ollama_cloud` in `server.json`, followed by a runtime restart. PhotoAgain does not set these options, inspect the runtime process, install/pull models, or manage the runtime. Review the [Ollama FAQ](https://docs.ollama.com/faq) yourself before opting in.

The adapter's real transport is fixed to `http://127.0.0.1:11434`. There is no endpoint flag. An ephemeral session disables proxy configuration, credential storage, cookies and URL cache. Redirects and authentication challenges are refused. Only `GET /api/tags`, `POST /api/show` and `POST /api/chat` are permitted. The transport caps each response at 1 MiB while receiving it, uses 30-second request and 90-second resource timeouts per request, and propagates task cancellation. These constrain this client's requests; they do not attest the server's behavior. The three sequential requests can take longer than 90 seconds in total.

## Synthetic example

Run from the package root. The demo and hints outputs must be new. The fake model name below is a placeholder for an **already installed exact local tag**; nothing downloads it.

```sh
swift run photoagain demo --output /tmp/photoagain-local-demo

# Pure argument validation: no file inspection, image reads or runtime contact.
swift run photoagain group-hints \
  --input /tmp/photoagain-local-demo/synthetic-1.png \
  --input /tmp/photoagain-local-demo/synthetic-2.png \
  --model example-vision:local \
  --output /tmp/photoagain-local-demo/hints.json \
  --acknowledge-runtime user-confirmed --check-only true

# Only after configuring/reviewing your runtime and replacing the model tag:
swift run photoagain group-hints \
  --input /tmp/photoagain-local-demo/synthetic-1.png \
  --input /tmp/photoagain-local-demo/synthetic-2.png \
  --model example-vision:local \
  --output /tmp/photoagain-local-demo/hints.json \
  --acknowledge-runtime user-confirmed
```

The second form sends preview pixels to the local runtime. This command was **not** run against a real runtime during implementation. `--check-only true` checks option syntax, count, extensions and model-name restrictions only; it does not establish file existence, safe output availability, valid image contents, installed models or vision support. `photoagain --help` also makes no runtime calls.

Supply exactly 2–4 explicit JPEG/PNG/single-frame HEIC/HEIF files in the intended comparison order. No directory expansion, symlinks, duplicate files, library scan or previous private manifest is used. The missing-acknowledgement error occurs before file metadata, image reads or network operations. Existing outputs fail before any image reads or network requests. SafeIO performs exclusive creation with mode 0600 at write time.

Inputs retain the native limits of 50 MB compressed and 100 megapixels. ImageIO validates type, frame count and dimensions before decoding a thumbnail. Orientation is applied, the image is redrawn into a fresh RGB bitmap, and JPEG previews of at most 1,280 pixels per edge and 2 MB each are kept in memory. Source EXIF/GPS/arbitrary metadata is not copied. The adapter sends base64 previews only after tags/show metadata passes; it does not send source filenames or paths. There is no persistent preview cache. This is not guaranteed secure memory erasure, and the runtime may persist what it receives.

## Model gate and contract

The exact model tag must appear once in `/api/tags`, with a nonempty SHA-256-format digest and positive finite size. `/api/show` must advertise `vision`. Remote/cloud model-name markers, remote/cloud metadata keys and remote/cloud capabilities are refused. License or template text containing ordinary URLs is not a remote marker and is never executed by the client. These are conservative metadata checks, not a cryptographic check of local weights or proof of offline inference. An uncooperative local server can misrepresent metadata or change a model between requests.

`/api/chat` receives a JSON Schema via `format`, `stream: false`, no tools, temperature 0 and a 2,048-token prediction limit. Completion must be an assistant message with `done: true`, `done_reason: stop`, and no tool calls. The system instruction treats depicted text as untrusted data. Local parsing independently enforces a closed schema; a prompt instruction alone is not the safeguard.

The output is a separate `GroupHintsDocument`, schema version 1. It has `capability: groupComparison.checkRegions`, a fresh UUID `requestID`, provider/adapter version, exact model tag/digest and `runtimeTrust: user-confirmed-not-attested`. Its `comparison.datasetID` equals the request ID. `comparison.memberIDs` is the exact ordered set `asset-0001` through the supplied count. These IDs belong to this fresh request, even if native evidence uses the same ordinal strings. This is a user-specified comparison set, not a claim that Vision found a similarity group.

The model payload permits only:

- `schemaVersion`, `datasetID`, exact ordered `memberIDs`, `abstained`, and up to eight `hints`.
- Each hint has unique known `memberIDs`, a category (`focus`, `exposure`, `framing`, `occlusion`) and region (`wholeFrame`, `upperLeft`, `upperRight`, `center`, `lowerLeft`, `lowerRight`). These are regions on the displayed, orientation-corrected image; no numerical coordinates or confidence scores are accepted.
- Abstention requires no hints; non-abstention requires at least one. Duplicate hints, unknown keys, foreign/duplicate IDs, invalid enum values, incompatible schemas and model payloads over 32 KiB are rejected.

Hints ask the person to check a possible visible difference in a region. They are not preferred-photo IDs, a global ranking, identity/emotion/milestone assertions, freeform commands or verified visual facts. Valid schema can still describe a wrong difference. The final file contains no model prose, images/base64, embeddings, credentials, original filenames or paths. It does disclose the selected model tag/digest. Native recommendation and explicit decision files are neither read nor rewritten by this command. Hints do not feed into `Policy` or `DecisionLedger`.

The older core `GroupComparisonDocument` preferred-ID contract is separate and is not used by this adapter. The generic CLI `validate` command currently validates native documents only; library callers validate the new payload with `GroupHints.decode(_:datasetID:memberIDs:)` against their known request and ordered IDs.

## Developer API and verification

```swift
let adapter = OllamaAdapter() // real fixed-loopback transport, only on compare/write
let hints = try await adapter.compare(
  inputURLs: explicitlySelectedFiles,
  model: exactLocalTag,
  acknowledgedRuntime: true)
// Or writeHints(..., output: newOutputURL) for preflight + exclusive creation.
```

`OllamaTransport.send(_:maximumBytes:)` is the injection point for deterministic tests. Custom implementations are trusted developer code and must honor cancellation, the response limit and intended locality; the default client's endpoint policy cannot constrain arbitrary injected code. Core and Vision consumers need not link `PhotoAgainOllama`.

```sh
swift test
python3 Tests/cli_smoke.py /path/to/built/photoagain
python3 Tests/local_cli_smoke.py /path/to/built/photoagain
```

The tests use generated images, mock metadata/model responses and an unresumed URLSession task for the redirect delegate check. They cover acknowledgement ordering, closed output schema, request binding, local/vision metadata gates, timeout/error/oversize propagation, preview bounds/orientation/metadata stripping, unchanged policy/decision bytes, cancellation, and no-clobber. They do not establish real-model quality, real-runtime compatibility, runtime offline behavior, real-photo privacy guarantees, HEIC decoder coverage, or server-side retention policy.

Official API references: [tags](https://docs.ollama.com/api/tags), [show model details](https://docs.ollama.com/api-reference/show-model-details), [chat](https://docs.ollama.com/api/chat), [structured outputs](https://docs.ollama.com/capabilities/structured-outputs).
