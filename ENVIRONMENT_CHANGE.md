# Explicit external-environment comparison

Reference machine: Windows x64, Python3.12.14, NumPy2.5.4, Pillow12.3.0. The local reference interpreter is a bundled runtime, not evidence that actions/setup-python provides an official Windows binary of the same patch release.

The [official Python3.12.14 release page](https://www.python.org/downloads/release/python-31214/) states it is source-only and that3.12.10 was the last3.12 release with binary installers. The [official Actions versions manifest](https://raw.githubusercontent.com/actions/python-versions/main/versions-manifest.json) contains3.12.14 Linux/RHEL builds but no Windows x64 artifact. The3.12.10 Windows x64 artifact was found in that manifest and its download URL returned HTTP200.

Therefore this new repository explicitly uses Python3.12.10 on Windows x64. It does not alter or overwrite the earlier3.12.14 draft or reference results. This decision was made before remote measurement and is recorded in workflow/provenance, rather than silently upgrading/downgrading on failure. Both packages retain the reference versions and use the exact cp312/win_amd64 wheels selected from official PyPI metadata, with SHA256 pins.

Unchanged: all12 frozen DLL bytes, all53 representations from18 source contents, codec behavior, input hashes,9 repetitions per method/input, random order, and3 preselected sequential sessions. The archive SHA256 is0ff26aa0363b32129b4079406145632126bae29886da65563159ad52f782b894.

Main analysis is paired method ratios within each remote session. Between-machine absolute time differences include interpreter, OS image, memory, cloud scheduling and hardware differences; they cannot be attributed entirely to CPU microarchitecture. A new VM session does not certify a unique physical host or a different processor model. Keep every failed/negative session and record actual reported CPU/image/version information.

Preparation checks only verify metadata, artifact availability and syntax. Remote execution and DLL loading are established only by actual workflow logs and output files. No alternative dependency is substituted when a pin is unavailable.
