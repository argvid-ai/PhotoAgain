# Run PhotoAgain locally

[Back to the project](../README.md) · [Contribute](../CONTRIBUTING.md)

## Try it without personal photos

Requires macOS 14 or later and a Swift 6 toolchain. Native aesthetics requires macOS 15; unavailable signals are recorded explicitly. There are no external Swift package dependencies.

```sh
swift test
swift run photoagain --help
swift run photoagain demo --output /tmp/photoagain-first-demo
```

The output directory must not exist. The demo generates three geometric PNG fixtures and produces `evidence.json`, `recipe.json`, and `recommendations.json`. It exercises the pipeline; these synthetic fixtures do **not** measure real-photo selection quality. Native services may be unavailable inside restricted execution environments; inspect the `missing` signals rather than treating a successful command as proof that every Vision request ran.

## Analyze an explicit batch

```sh
swift run photoagain analyze --input ./my-test-images --output ./evidence.json --private-manifest ./inputs.private.json
swift run photoagain recommend --input ./evidence.json --recipe ./Examples/keep-variety.json --output ./recommendations.json
swift run photoagain validate --input ./recommendations.json --kind recommendations --evidence ./evidence.json
```

Only explicitly supplied files or a flat directory are read, with a maximum of 4,096 directory entries. The first slice accepts up to 128 JPEG, PNG, or single-frame HEIC/HEIF images, at most 50 MB compressed and 100 megapixels each. Analysis uses oriented thumbnails with a maximum edge of 2,560 pixels. It does not scan Photos, recurse through your disk, edit originals, upload images, or perform deletion.

Existing output files are never overwritten. Paths containing user-controlled symbolic links are rejected. Public/private destinations are checked for collisions and existing files before analysis; writing two files is **not transactional**. If the private write fails after public evidence is created, the command reports the incomplete pair and exits with failure.

`--private-manifest` is optional and requires a new filename ending in `.private.json`. This separate file is labeled `private-local-input-map`, created with mode 0600, and excluded by the candidate's `.gitignore`. It contains the dataset ID, exact asset-ID-to-source-path mapping and local file identity from the same expanded inputs. Keep it private. Public evidence contains no source paths or media bytes. Library callers can recheck this mapping with `PrivateInputManifest.validate(referencing:)`; changed inputs are rejected.

Every analysis creates a fresh UUID `datasetID`, including reanalysis of the same files. Evidence, decisions, recommendations, group comparisons and private mappings must agree on that ID. Ordinal asset IDs are meaningful only within that dataset. Do not copy an old ledger into a new batch or rewrite its dataset ID to bypass this check.

## Change the selection goal

Edit a small recipe instead of changing a model:

```json
{
  "schemaVersion": 1,
  "goal": "keep-variety",
  "desiredCount": 3,
  "minimumMargin": 0.05
}
```

- `representative`: experimental ranking from native aesthetics evidence.
- `keep-variety`: additionally proposes at most one item per experimental similarity component. This is not semantic coverage, event understanding, or a calibrated diversity metric.
- `minimumMargin`: requests abstention when scores are too close; it is an experimental policy setting, not a confidence probability.

The current `keep-variety` policy conservatively checks close pairs in every unused similarity group before choosing the groups that fill the requested slots. A low-scoring tied group can therefore cause complete abstention even when an unrelated higher-scoring photo clearly fills the request. For example, with one requested slot and margin 0.05, an ungrouped 0.90 candidate plus a grouped 0.20/0.19 pair abstains. This global tie veto is an experimental policy limitation.

Explicit keep/exclude decisions are supplied separately with `--decisions`. Suggestions never rewrite that ledger. Undo references a prior decision; an unclicked suggestion is not a rejection. Start a ledger using the exact `datasetID` from the corresponding evidence and IDs checked against its private mapping:

```json
{
  "schemaVersion": 1,
  "datasetID": "COPY-EXACT-UUID-FROM-EVIDENCE",
  "entries": [
    {"id": "decision-1", "assetID": "asset-0001", "action": "keep"},
    {"id": "decision-2", "assetID": "asset-0001", "action": "undo", "undoDecisionID": "decision-1"}
  ]
}
```

The placeholder must be replaced with the evidence UUID before validation. Validate with `photoagain validate --kind decisions --input decisions.json --evidence evidence.json`, then pass `--decisions decisions.json` to `recommend`. An omitted ledger means a new empty ledger bound to the current evidence. Unbound older candidate documents are rejected; no automatic migration is attempted.

`RecommendationDocument.validate(referencing:)` checks schema, dataset, recipe, unique known IDs and counts. Suggestions cannot exceed slots left after explicit keeps. Explicit keeps may exceed the desired count; partial results require abstention. This validates structural invariants, not the truth of generated reasoning or selection quality.

## What is available now

| Component | Purpose |
|---|---|
| `PhotoAgainCore` | Versioned evidence, recipes, decisions, validation and deterministic policy |
| `PhotoAgainVision` | Bounded image loading and Apple Vision reference analyzer |
| `PhotoAgainOllama` | Optional fixed-loopback Ollama check-region hints; separate from native policy |
| `photoagain` | Generated demo, explicit batch analysis, recommendation, validation and opt-in group hints |
| `Examples` | Editable recipes |

Native face count and capture-quality evidence are descriptive. Capture quality is not identity recognition, a blink detector, or a universal measure of a meaningful photograph. The default policy does not rank different providers' scores together.

## Optional local-model check regions

`group-hints` compares 2–4 explicitly supplied files through a user-controlled Ollama runtime. It emits fixed-category regions to inspect, with abstention; it supplies no score or preferred photo IDs and cannot change native recommendations or decisions. The adapter has mock-transport coverage only: **no real model inference has been tested**.

```sh
swift run photoagain group-hints \
  --input /tmp/photoagain-first-demo/synthetic-1.png \
  --input /tmp/photoagain-first-demo/synthetic-2.png \
  --model example-vision:local --output /tmp/photoagain-first-demo/hints.json \
  --acknowledge-runtime user-confirmed --check-only true
```

This example only validates arguments; it reads no image/file metadata and contacts no runtime. For inference, first configure and review your runtime, replace the placeholder with an already installed exact local vision tag, then remove `--check-only true`. Missing acknowledgement fails before reads or requests. Inference sends metadata-stripped, oriented JPEG previews (maximum edge 1,280) to fixed `127.0.0.1:11434`; it never downloads a model. Loopback cannot certify that a runtime stays offline. Read [local-model setup, trust and limits](LOCAL-MODELS.md) before opting in.


## Check a code change

```sh
swift test
photoagain_bin_dir="$(swift build --show-bin-path)"
python3 Tests/cli_smoke.py "$photoagain_bin_dir/photoagain"
python3 Tests/local_cli_smoke.py "$photoagain_bin_dir/photoagain"
```

The adapter smoke check exercises syntax and the no-transmission check-only path. XCTest adapter tests use a mock transport; these checks do not certify a real model or real-photo usefulness. Documentation-only changes need link, scope and example checks.
