# Dependency and distribution inventory

`Package.swift` declares no external Swift package dependency. This inventory distinguishes repository material from separately supplied build/runtime components; it does not relicense those components.

| Layer | Dependency | Included in this source bundle? |
|---|---|---|
| Build | Swift 6 and macOS SDK | No; supplied by the developer's toolchain under their respective terms |
| Native analysis / images | Apple Vision, ImageIO, CoreGraphics, UniformTypeIdentifiers | System API references only; no Apple model weights bundled |
| Files / transport | Foundation and Darwin | Toolchain/system APIs; no vendored implementation |
| Optional inference | User-installed Ollama runtime | No installer, binary or service bundled |
| Optional visual model | Model selected by the developer | No weights bundled or downloaded automatically; check exact model and version terms |
| Examples / tests | Runtime-generated geometric fixtures | Original synthetic fixtures; no personal photograph dataset |
| Tests | XCTest and Python 3 standard library for CLI smoke checks | Supplied by developer's environment; no third-party test package |
| Site | Original HTML/CSS/JS/SVG, plus explicitly listed promotional screenshots | Original site code follows Apache-2.0; raster screenshot rights are separate in the [asset manifest](site/assets/RIGHTS.md) |

No third-party photo-selection project's source has been vendored into the initial candidate. No third-party fonts, model weights or photo datasets are distributed by the framework. A screenshot's depicted content is governed by its asset entry, not treated as a test dataset.

Before adding a dependency, model, dataset, font or copied snippet, record source, exact version where applicable, license, distribution scope and required notices. Check runtime and weights separately: a runtime's license does not establish permission to redistribute or commercially use every model it can load. Keep this inventory current with the actual release contents. See [rights](RIGHTS.md) and [local model boundaries](LOCAL-MODELS.md).
