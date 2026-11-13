# Contributing to PhotoAgain

A small fix, test, documentation improvement or synthetic example can come straight as a pull request. For a new provider, schema change or architecture change, open an issue first so we can agree on scope and compatibility. See [contribution ideas](docs/CONTRIBUTION-IDEAS.md) and [governance](GOVERNANCE.md).

## Rights and sign-off

Project code and documentation are offered under [Apache-2.0](LICENSE), subject to separately marked material. You retain your rights; contributing does not assign copyright. There is no CLA or copyright assignment. Intentional contributions for inclusion are under Apache-2.0 unless explicitly stated otherwise; discuss any differently licensed material before submitting it. Preserve its provenance, license and required notices.

Every contribution commit must carry your sign-off to certify the [Developer Certificate of Origin 1.1](DCO). Read it before signing:

```sh
git commit -s
```

Git adds `Signed-off-by: Your Name <your-email@example.com>` using your configured identity. Sign only when you can make the DCO certification; never sign on another person's behalf. This attests provenance and your right to submit, not transfer of ownership. Commit metadata and sign-offs are public, retained indefinitely and may be redistributed. Choose an appropriate public commit email before committing. A sign-off is distinct from a cryptographic commit signature.

If work belongs to an employer, client or another rights holder, obtain the necessary authority before submitting. A sign-off does not resolve disputed ownership or approve historical imports. See [rights and release scope](docs/RIGHTS.md).

For AI-assisted changes, briefly describe the tool's relevant role (for example, generated a parser draft) and what a person reviewed or tested. You remain responsible for provenance and correctness. Do not publish private prompts, confidential context or personal data. AI assistance is not proof of ownership or license compatibility.

## A useful pull request

Explain the problem, resulting behavior and checks performed. Keep a change small enough to review. Document schema or behavior changes and add meaningful verification appropriate to the change. For code changes, run `swift test` and the relevant CLI smoke checks described in the [quick start](docs/QUICKSTART.md). Documentation-only changes need link and factual checks, not a new test suite.

Use generated geometric fixtures or a minimal synthetic reproduction. **Do not upload private photos**, face crops, embeddings, personal filenames, absolute paths, credentials or raw runtime logs to an issue or PR. Describe a failure without the original media; sanitize output before sharing. See [boundaries](docs/BOUNDARIES.md).

Maintainers review scope, behavior, provenance, notices and sign-offs before merging. This repository does not currently install a DCO enforcement bot or required CI check; the sign-off policy requires review. No response time or merge is guaranteed.
