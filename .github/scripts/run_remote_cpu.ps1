# Frozen protocol wrapper for explicitly dispatched remote CI jobs.
# No compilation, source substitution, CPU certification, or result filtering.
param(
    [Parameter(Mandatory=$true)][string]$ArchivePath,
    [Parameter(Mandatory=$true)][string]$ExpectedSha256,
    [ValidateSet('correctness','benchmark')][string]$Mode='correctness',
    [ValidateRange(1,3)][int]$Session=1,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory
)
$ErrorActionPreference='Stop'

function Write-JsonFile([string]$Path, $Value) {
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-ReportedEnvironment {
    $cpu=Get-CimInstance Win32_Processor | Select-Object Name,Manufacturer,ProcessorId,Family,Stepping,Revision,Architecture,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
    $computer=Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,HypervisorPresent,TotalPhysicalMemory
    $os=Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture
    $power=(& powercfg.exe /GETACTIVESCHEME 2>&1 | Out-String).Trim()
    [ordered]@{
        utc=[DateTime]::UtcNow.ToString('o')
        cpu_reported=@($cpu)
        computer_reported=$computer
        os_reported=$os
        power_scheme_reported=$power
        limitation='Guest-visible CPU fields and ProcessorId are not a unique physical-host certificate. Cloud VM evidence is distinct from bare-metal evidence.'
    }
}

if ([string]::IsNullOrWhiteSpace($env:GITHUB_WORKSPACE)) { throw 'GITHUB_WORKSPACE must identify the checked-out repository.' }
$workspace=[System.IO.Path]::GetFullPath($env:GITHUB_WORKSPACE)
$evidence=[System.IO.Path]::GetFullPath($EvidenceDirectory)
$workspacePrefix=$workspace.TrimEnd([char[]](92,47))+[System.IO.Path]::DirectorySeparatorChar
if (-not $evidence.StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Evidence directory must stay within the checked-out repository.' }
if (Test-Path -LiteralPath $evidence) { throw 'Refusing to overwrite an existing evidence directory.' }
New-Item -ItemType Directory -Path $evidence | Out-Null
$status=[ordered]@{ complete=$false; mode=$Mode; session=$Session; benchmark_completed=$false; physical_cpu_certified=$false }

try {
    $archive=[System.IO.Path]::GetFullPath((Join-Path $workspace $ArchivePath))
    if (-not $archive.StartsWith($workspacePrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Archive must stay within the checked-out repository.' }
    if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw 'Frozen archive not found in repository.' }
    if ([System.IO.Path]::GetExtension($archive) -ne '.zip') { throw 'Expected a ZIP archive.' }
    if ($ExpectedSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'ExpectedSha256 must contain 64 hexadecimal characters.' }
    $actualHash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Archive hash mismatch; do not regenerate manifests to bypass it.' }

    $record=[ordered]@{
        purpose='Auxiliary external replication on a remote GitHub-hosted Windows VM; not automatic bare-metal or CPU-model certification.'
        mode=$Mode
        session=$Session
        repetitions_if_benchmark=9
        archive_relative_path=$ArchivePath
        archive_sha256=$actualHash
        repository=$env:GITHUB_REPOSITORY
        source_commit=$env:GITHUB_SHA
        workflow_ref=$env:GITHUB_WORKFLOW_REF
        run_id=$env:GITHUB_RUN_ID
        run_attempt=$env:GITHUB_RUN_ATTEMPT
        run_url=($env:GITHUB_SERVER_URL+'/'+$env:GITHUB_REPOSITORY+'/actions/runs/'+$env:GITHUB_RUN_ID)
        runner_name=$env:RUNNER_NAME
        runner_environment=$env:RUNNER_ENVIRONMENT
        requested_runner=$env:REQUESTED_RUNNER
        reference_python_version=$env:REFERENCE_PYTHON_VERSION
        requested_remote_python_version=$env:REMOTE_PYTHON_VERSION
        environment_change='Reference Python3.12.14 has no official Windows x64 Actions artifact. Remote Python3.12.10 is an explicit documented environment comparison; fixed DLL/data/protocol are unchanged.'
        image_os=$env:ImageOS
        image_version=$env:ImageVersion
        environment_declaration='remote-cloud-vm'
        claimed_independent_physical_hosts='unknown; fresh VM sessions may share the same CPU model or physical host'
        selection='Session count selected before measurements; retain all sessions and all negative values.'
    }
    Write-JsonFile (Join-Path $evidence 'remote_provenance.json') $record
    Write-JsonFile (Join-Path $evidence 'environment_before.json') (Get-ReportedEnvironment)
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 20 ProcessName,CPU,WorkingSet64 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidence 'process_snapshot_before.json') -Encoding utf8
    & python --version 2>&1 | Set-Content -LiteralPath (Join-Path $evidence 'python_version.txt') -Encoding utf8
    & python -m pip freeze 2>&1 | Set-Content -LiteralPath (Join-Path $evidence 'pip_freeze.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw 'Cannot record Python environment.' }
    & python -c 'import sys,json,numpy,PIL; d={"python":list(sys.version_info[:3]),"numpy":numpy.__version__,"Pillow":PIL.__version__,"pointer_bits":64 if sys.maxsize>2**32 else 32}; print(json.dumps(d)); assert sys.version_info[:3]==(3,12,10); assert numpy.__version__=="2.5.4"; assert PIL.__version__=="12.3.0"; assert sys.maxsize>2**32' 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'pinned_environment_check.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Unexpected environment; do not silently substitute dependency versions.' }

    $extract=Join-Path $env:RUNNER_TEMP ('dna-frozen-'+$env:GITHUB_RUN_ID+'-'+$env:GITHUB_RUN_ATTEMPT+'-'+$Session)
    if (Test-Path -LiteralPath $extract) { throw 'Refusing to reuse an existing extraction directory.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $extract
    $entries=@(Get-ChildItem -LiteralPath $extract -Filter run.py -Recurse -File | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'binary_manifest.json')) -and
        (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'data_manifest.json'))
    })
    if ($entries.Count -ne 1) { throw 'Archive must contain exactly one frozen package root with run.py and both manifests.' }
    $entry=$entries[0]
    $binary=Get-Content -LiteralPath (Join-Path $entry.DirectoryName 'binary_manifest.json') -Raw | ConvertFrom-Json
    $names=@($binary.PSObject.Properties.Name)
    $expected=@('clang_original','clang_prevk','clang_unroll','clang_clz','clang_binary','clang_getterprevk','msvc_original','msvc_prevk','msvc_unroll','msvc_clz','msvc_binary','msvc_getterprevk')
    if (@(Compare-Object ($expected | Sort-Object) ($names | Sort-Object)).Count -ne 0) { throw 'Expected the complete frozen set of 12 methods.' }
    Copy-Item -LiteralPath (Join-Path $entry.DirectoryName 'binary_manifest.json') -Destination (Join-Path $evidence 'binary_manifest.json')
    Copy-Item -LiteralPath (Join-Path $entry.DirectoryName 'data_manifest.json') -Destination (Join-Path $evidence 'data_manifest.json')
    $label='github-remote-'+$env:GITHUB_RUN_ID+'-attempt'+$env:GITHUB_RUN_ATTEMPT+'-session'+$Session
    & python $entry.FullName --check-only --environment vm --machine-label $label --output (Join-Path $evidence 'correctness') 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'correctness_console.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Frozen correctness checks failed.' }
    if ($Mode -eq 'benchmark') {
        & python $entry.FullName --environment vm --machine-label $label --repeats 9 --output (Join-Path $evidence 'benchmark') 2>&1 | Tee-Object -FilePath (Join-Path $evidence 'benchmark_console.txt')
        if ($LASTEXITCODE -ne 0) { throw 'Frozen benchmark failed; retain its partial evidence.' }
        $summary=Get-Content -LiteralPath (Join-Path $evidence 'benchmark/summary.json') -Raw | ConvertFrom-Json
        if (-not $summary.complete -or $summary.checks -ne 53 -or $summary.method_count -ne 12 -or $summary.records -ne 5724) { throw 'Incomplete benchmark result.' }
        $status.benchmark_completed=$true
    }
    $status.complete=$true
} catch {
    $status.error=$_.Exception.Message
    throw
} finally {
    $status.finished_utc=[DateTime]::UtcNow.ToString('o')
    Write-JsonFile (Join-Path $evidence 'status.json') $status
    try { Write-JsonFile (Join-Path $evidence 'environment_after.json') (Get-ReportedEnvironment) } catch {
        $_.Exception.Message | Set-Content -LiteralPath (Join-Path $evidence 'environment_after_error.txt') -Encoding utf8
    }
}
