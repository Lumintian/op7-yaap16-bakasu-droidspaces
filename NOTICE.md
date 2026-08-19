# Upstream notice

This repository is a build wrapper and patch set. It does not vendor upstream source trees or manager APKs.

Builds fetch these immutable revisions:

- YAAP `kernel_oneplus_sm8150` at `3a3c6bb4fa9cbeca5aed90f46ba2d907980e2b56` (Linux kernel licensing applies).
- ReSukiSU at `06390a6acbb7e966b3e1cda00fc1b93e89f11086` (see the upstream repository for its GPL-3.0 license and notices).
- AnyKernel3 at `e4b1bb25ca2aabcfd57f694a5998d87130701b71` (see its upstream LICENSE).
- Android Clang prebuilt tree at `9916fb51ccb914d62d35ad9a7b9b21d2ef046928` (its bundled notices apply).

The patch under `patches/` modifies Linux kernel source and is intended to be distributed under the same GPL-2.0 terms that govern the patched kernel files. Generated artifacts combine upstream components; retain all included license files and comply with each upstream license when redistributing binaries.

No warranty is provided. Device flashing remains the operator's responsibility.
