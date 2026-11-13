# PhotoAgain boundaries

PhotoAgain is a local photo-selection experiment framework. It is not a photo backup service, facial identity database or autonomous deletion tool.

## Native reference

The native provider uses Apple system frameworks on explicitly selected files. Analysis measures image properties and produces candidate comparisons. Scores do not measure how much a memory matters. Experimental thresholds must be reported as such.

The standalone candidate is not yet the engine used by the separately developed Mac application. It uses related system primitives, but equivalence with the application policy has not been established. Adoption requires compatibility and regression checks. The existing application and its user data remain unchanged.

## External local runtimes

An optional external runtime is a separate recipient of derived image data, even when the endpoint is on the same computer. Loopback is not proof that a service will never relay, log or retain data. Runtime configuration and model selection must be explicitly checked by the developer; the framework must never label a user assertion as a verified network audit.

External group hints are a shadow experiment. They do not silently change native rankings, user decisions or exports. The framework validates output IDs, types, bounds and missing values; valid JSON still does not guarantee accurate visual judgments.

No automatic runtime or model installation, remote endpoint, tool execution, shell execution or unrequested photo upload is part of the default workflow.

## Data and sharing

- Only use media you are authorized to process. Explicitly choose the input files or directory.
- Keep originals unchanged. Do not use model output as a filename, command or upload instruction.
- Public summaries omit original filenames and absolute paths. Opaque IDs and visual evidence may still be sensitive in context; inspect a report before sharing it.
- Never put private media, full task state, derived face crops, embeddings or runtime logs into public issues by default.
- A synthetic demo tests plumbing, not real-world selection accuracy.

## Licensing and integration

PhotoAgain is a standalone experimental framework maintained in the separate `argvid-ai/PhotoAgain` repository. It is not currently integrated with Argvid. The repository's Apache-2.0 license permits commercial reuse, including by competitors; it does not license a shipping application's private code or assets. Contributor rights remain with their holders. See [rights](RIGHTS.md), [dependencies](DEPENDENCIES.md) and [contributing](../CONTRIBUTING.md).

Promotional screenshots illustrate application concepts and are separately licensed in the [asset manifest](site/assets/RIGHTS.md). They do not establish framework parity, release readiness, model accuracy or real-photo evaluation results. Synthetic fixtures verify plumbing, not selection quality in a person's photo library.
