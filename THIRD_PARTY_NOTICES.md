# Third-party components

None of these are bundled in this repository or its Releases. `run.bat`
downloads them on the user's PC from their official sources, pinned by
version/commit and verified by SHA-256 (see `tools/common.ps1`).

| Component | Source | License |
| --- | --- | --- |
| psxrecomp (static recompiler, runtime, OpenBIOS backend) | github.com/mstan/psxrecomp @ f60aae2 | PolyForm Noncommercial 1.0.0 (see its LICENSE; noncommercial use only) |
| recomp-ui (launcher UI) | github.com/RetroPortingToolKit/recomp-ui @ 5de138a | see its LICENSE |
| recomp-net | github.com/RetroPortingToolKit/recomp-net @ c58f125 | see its LICENSE |
| rbengine | github.com/RetroPortingToolKit/rbengine @ 2a03e73 | see its LICENSE |
| cmake-clang-v1 toolchain (LLVM-MinGW, CMake, Ninja, Python, SDL3, zlib) | github.com/RetroPortingToolKit/RetroPorting-Toolchains v1.0.14 | per component (see LICENSE.TXT inside the pack) |
| OpenBIOS | shipped by psxrecomp | MIT |

The psxrecomp license is noncommercial: the resulting build may not be sold or
used commercially.
