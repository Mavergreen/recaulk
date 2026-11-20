# 10.9's public KPI export lists

Each `<bundle id>.txt` lists every symbol one of 10.9's KPI symbol-set kexts exports, one per line, sorted
(`LC_ALL=C`). `tests/kext-imports.sh` holds RecaulkKPI.kext's imports to the lists of the libraries its
`Info.plist` names.

- Source: `/System/Library/Extensions/System.kext/PlugIns/{BSDKernel,Libkern,Mach,Unsupported}.kext` on
  Mac OS X 10.9.5 (Darwin 13.4.0, `root:xnu-2422.115.15~1/RELEASE_X86_64`), captured 2026-11-20.
- Method: `sh build/capture-kpi-fixture.sh` on 10.9 (clang22's `llvm-nm -j`).
- Only these four: the kext may name no other library, and never `com.apple.kpi.private`.
