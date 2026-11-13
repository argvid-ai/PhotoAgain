# Evaluate usefulness, not just a score

The generated demo establishes that commands and contracts work. It cannot establish photo-selection quality. This repository contains **no measured real-photo quality or M3 performance benchmark yet**.

## One small, repeatable experiment

1. Choose media whose owner explicitly permits this use. Keep a private asset map separate from a shareable report. A photo available online is not automatically a redistributable benchmark.
2. Pick a concrete task: one representative from a burst, a small varied set from an outing, or a set the owner wants to revisit. These have different success criteria.
3. Before seeing recommendations, have the owner mark important-to-keep items and acceptable alternatives. These are that person's judgments, not universal aesthetic truth.
4. Compare the same batch and requested count under a recorded recipe. Keep tuning batches separate from evaluation batches. Preserve native results when testing a new provider.
5. Record time to review, missed important items, unnecessary suggestions, corrections, and explicit abstentions. Separately record end-to-end latency, peak memory and missing native signals.
6. Repeat at a genuine next organizing opportunity. A one-off novel result and natural repeat use answer different questions.

## Local-model shadow evaluation

The first optional provider gives typed visible-difference hints. It does not change native ranking. Assess whether a hint is correct, useful, redundant or misleading, and whether it reduces review effort. Do not compare arbitrary providers' numeric scores as if they shared a calibrated scale.

Record model digest, runtime/version, preprocessing, OS, batch size and whether a cold load was included. Report failure and cancellation cases. A fast malformed response is not a success; a schema-valid response may still be visually wrong.

## What to share

Use [the empty CSV template](../Examples/evaluation-template.csv) for aggregate results. Share exact command/recipe/provider versions and anonymized failure categories. Do not attach original media, private manifests, face crops, embeddings, model logs, paths, or personal annotations without a separate rights and privacy check.

Avoid headline accuracy claims without task definition, denominator, sample selection and limitations. Do not turn a few cooperative testers into a population estimate. A useful first contribution can simply reproduce one failure on a licensed or generated fixture and demonstrate a bounded fix.

## Promotion gate

Only consider moving an experimental policy into the Mac app after it improves the chosen task without increasing important omissions or corrective work, passes compatibility/recovery checks, and is measured on the target hardware. The acceptable tradeoff depends on the task and user; this project does not declare a universal percentage threshold.
