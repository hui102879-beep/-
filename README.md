# Frozen lossless-codec external replication

This repository is prepared locally for an explicitly requested GitHub Actions run. Preparation alone is not a completed remote measurement.

Protocol: 12 frozen CharLS2.4.5 DLL variants,53 image representations from18 sources,9 repetitions per method/input,3 sequential VM sessions. All methods and negative/failed sessions are retained. CPU model and image version are recorded; a Windows runner label does not certify a physical CPU model or bare-metal execution.

See ENVIRONMENT_CHANGE.md: this repository explicitly uses official Windows Python3.12.10 because the original3.12.14 setup-python configuration has no Windows artifact. DLLs/data and NumPy/Pillow versions remain unchanged. Do not claim identical cross-machine environments.

The archive is fixed at artifacts/second_cpu_package.zip. Its SHA256 is:
0ff26aa0363b32129b4079406145632126bae29886da65563159ad52f782b894

After this repository is on the default branch, dispatch the workflow first in correctness mode. On success dispatch benchmark mode with sessions=3, runner_label=windows-2022, archive_path=artifacts/second_cpu_package.zip, and the SHA256 above. Preserve all artifacts and run URLs. The workflow only responds to workflow_dispatch.

Example GitHub CLI commands for the account/repository selected by the user:

```powershell
gh workflow run windows-remote-cpu.yml -f mode=correctness -f sessions=1 -f runner_label=windows-2022 -f archive_path=artifacts/second_cpu_package.zip -f archive_sha256=0ff26aa0363b32129b4079406145632126bae29886da65563159ad52f782b894
gh workflow run windows-remote-cpu.yml -f mode=benchmark -f sessions=3 -f runner_label=windows-2022 -f archive_path=artifacts/second_cpu_package.zip -f archive_sha256=0ff26aa0363b32129b4079406145632126bae29886da65563159ad52f782b894
```

No correctness or benchmark job has been remotely executed by the preparation step. Local syntax checks do not establish CI success. Each completed benchmark session must contain5724 timing rows and exact checks for53 inputs and12 methods.

Source/data/binary provenance and CharLS license are contained in the archive. It consists only of fixed public research inputs and already-reviewed binaries/source; it does not include the local workspace, credentials or unpublished user documents.
