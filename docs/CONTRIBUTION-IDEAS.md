# Useful first contributions

These are starter tasks, not already published issues or assigned work. Small documentation fixes can go directly to a pull request; discuss a behavioral change before spending time on it. [How to contribute](../CONTRIBUTING.md).

| First task | A useful finished contribution | Keep out of scope |
|---|---|---|
| Make the first demo easier to understand | Reproduce the documented command; improve one confusing step with the observed platform/version | Claiming that geometric fixtures prove photographic quality |
| Pin one orientation failure | A small asymmetric generated fixture and assertions about actual pixel orientation, not only width/height | A private camera roll or broad image-pipeline rewrite |
| Investigate conservative variety abstention | Reproduce the documented low-score tie veto; propose a bounded rule and regression cases, then compare tradeoffs | Changing thresholds until one chosen example passes |
| Try a real local vision model | Exact local tag/digest, runtime setup, licensed/generated inputs, useful vs. misleading region hints and resource cost | Automatic model downloads, arbitrary cloud endpoints or merging uncalibrated scores |
| Explain a correction | A minimal synthetic example showing keep/exclude/undo and dataset validation | Treating an unclicked suggestion as an explicit rejection |

Time spent, feedback quality and reproducibility matter more than the number of adapters. A small fix with a clear test is a strong first contribution.

1. **Reproduce one selection failure.** Use a generated or clearly licensed example, state the expected choice and why, include the provider/recipe version, and show the observed result. Do not submit private family photos.
2. **Add an evidence provider.** Declare single-image and group-comparison capabilities separately. Return typed evidence or a missing reason; do not alter the explicit decision ledger. Include malformed output, cancellation and resource-limit tests.
3. **Improve a measured bottleneck.** Record hardware, OS, image count and dimensions, cold/warm cache and foreground responsiveness. Do not compare different datasets as if they measured the same speedup.

Changing a recipe is the easiest DIY entry. Adding another runtime is useful only when it answers a concrete task better or makes a known workflow easier. The project should not maintain many nearly identical adapters without users or tests.

Code license, model-weight license and evaluation-data rights are checked separately. Do not assume an upstream repository's license covers all downloadable weights or images.
