# Contracts and extension points

The framework treats **evidence**, **policy suggestions**, and **explicit decisions** as different records. A model is an observer, not an authority to delete a file or rewrite a user's choices.

## Data flow

```text
explicit local files → bounded preview → assetAnalysis evidence
                                         ↓
                             deterministic recipe policy
                                         ↓
                           suggestions + abstention/reasons

explicit keep/exclude/undo ledger ────────→ preserved user decisions

optional groupComparison provider ──────→ separate advisory document
```

Version 1 uses Codable JSON. Consumers must call validation after decoding: decoding alone does not establish schema compatibility, range validity, known asset membership, or correct capability. Missing observations remain missing; zero is a value, not an error fallback.

Each `EvidenceDocument` generates a fresh UUID `datasetID`. `DecisionLedger(datasetID:entries:)`, `RecommendationDocument`, `GroupComparisonDocument(datasetID:provider:groupID:assetIDs:preferredIDs:abstained:)` and `PrivateInputManifest` bind to that ID. `DecisionLedger.effective(knownIDs:datasetID:)` requires the expected dataset, and referencing validators reject other batches even when ordinal asset IDs match. `Policy.recommend(_:recipe:ledger:)` accepts an optional ledger and binds a default empty ledger to the current evidence. Recommendation validation additionally checks count and membership invariants. The unreleased version-1 candidate now requires dataset binding; older unbound documents fail decoding rather than being guessed or migrated.

`PrivateInputManifest(evidence:inputs:)` captures the same ordered `LocalInput` handles used by analysis, separately from public evidence. Its validator checks membership, dataset and current local file identity. `analyze --private-manifest NEW.private.json` opts into writing this 0600 private file; paired output preflight does not provide multi-file transactions.

## Provider identity

`Provider` records provider ID, model version, preprocessing version and capability. The native ranking accepts the exact native identity. Changing weights, normalization, preprocessing or provider is a new experimental condition, not permission to mix scores on the same scale.

Native evidence records `runtimeOS` separately from the logical adapter version; Apple internal model versions remain unavailable. Native aesthetics is normalized from Vision's overall score to 0…1. The margin in a recipe compares this score; it is not the probability that the selected image is better. Face capture quality is recorded without asserting correspondence between different faces in different images.

## Two capabilities

`assetAnalysis` describes a single input asset. `groupComparison` refers to a known set of members and must validate against the evidence batch. Supporting the first does not imply support for the second. Group advice must remain outside `Policy.recommend` until a separate, measured evaluation justifies a new policy.

## DIY without a model

Begin by changing `goal`, `desiredCount` and `minimumMargin` in a recipe. To experiment beyond the two built-in policies, consume validated `EvidenceDocument` in your own Swift executable and emit a separate result. Preserve explicit decisions and provenance. Do not relabel a custom score as native Vision evidence to bypass provider checks.

Report comparison conditions: OS/toolchain, image dimensions, provider and preprocessing version, recipe, missing signals, elapsed time, and human corrections. Photos, source paths and raw embeddings do not belong in a public performance report.

## Compatibility status

This is a pre-release candidate, not a stable published SDK contract. Breaking changes require a schema-version decision and migration notes. Adoption by the Mac app requires separate regression and migration work; shipping-app behavior is not silently replaced by this laboratory implementation.
