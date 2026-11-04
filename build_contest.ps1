param([switch]$VerifyOnly, [switch]$CheckPaths)
$ErrorActionPreference = 'Stop'
$buildStatus = $null
$evidence = $null
try {
    . (Join-Path $PSScriptRoot 'tools\pds_common.ps1')
    if ($CheckPaths) {
        $bin = Find-PdsBin -Executable 'pds_shell.exe' -ProjectRoot $PSScriptRoot
        $null = Get-DesignHashes $PSScriptRoot
        Write-Host "PDS tools: $bin"
        Write-Host "Project: $PSScriptRoot"
        Write-Host 'Path check passed. No build was started.'
        return
    }
    if ($VerifyOnly) {
        Assert-BuildManifest $PSScriptRoot
        Write-Host 'Verified current design hashes, bitstream hash and internal timing.'
        return
    }
    $bin = Find-PdsBin -Executable 'pds_shell.exe' -ProjectRoot $PSScriptRoot
    $before = Get-DesignHashes $PSScriptRoot
    $work = New-PdsWorkspace -Purpose build
    $evidence = Join-Path $PSScriptRoot ('build_evidence\' + (Split-Path -Leaf $work))
    $null = New-Item -ItemType Directory -Path $evidence -Force
    $buildStatus = [ordered]@{
        Status = 'running'; StartedAtUTC = [DateTime]::UtcNow.ToString('o')
        PdsBin = $bin; Workspace = $work; Inputs = $before; Evidence = $evidence
    }
    $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'status.json') -Encoding UTF8
    $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'latest_build.json') -Encoding UTF8
    Copy-DesignInputs -ProjectRoot $PSScriptRoot -Destination $work
    $staged = Get-DesignHashes $work
    foreach ($file in $before.Keys) {
        if ($staged[$file] -ne $before[$file]) { throw "Input changed while staging: $file. Retry build." }
    }
    Write-Host "PDS tools: $bin"
    Write-Host "Project: $PSScriptRoot"
    Write-Host "PDS workspace: $work"
    $log = Join-Path $work 'contest_build.log'
    $started = Get-Date
    try {
        Invoke-PdsTool -Executable (Join-Path $bin 'pds_shell.exe') -Arguments @('-project', (Join-Path $work 'hdmi_loop.pds'), '-run', 'gen_bit_stream') -WorkingDirectory $work -LogPath $log
    } finally {
        if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination (Join-Path $PSScriptRoot 'contest_build.log') -Force }
        # Failed reports remain separate from the last validated release.
        # Keep the actual failing paths available even on a different PC.
        foreach ($name in @('contest_build.log','report_timing','place_route')) {
            $path = Join-Path $work $name
            if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination (Join-Path $evidence $name) -Recurse -Force }
        }
    }
    if ((Get-Content -LiteralPath $log -Raw) -notmatch 'Generating Programming File done') { throw "Bitstream generation did not finish. See $log" }
    $bit = Get-Item -LiteralPath (Join-Path $work 'generate_bitstream\hdmi_loop.sbit')
    if ($bit.Length -eq 0 -or $bit.LastWriteTime -lt $started) { throw 'No fresh bitstream was generated.' }
    Assert-InternalTiming $work
    $after = Get-DesignHashes $PSScriptRoot
    if ($after.Count -ne $before.Count) { throw 'Design changed during build. No new bitstream published; rebuild.' }
    foreach ($file in $before.Keys) {
        if ($after[$file] -ne $before[$file]) { throw "Design changed during build: $file. No new bitstream published; rebuild." }
    }
    # Publish only after the complete build and timing validation have passed.
    foreach ($dir in @('generate_bitstream','report_timing')) {
        $dest = Join-Path $PSScriptRoot $dir
        $null = New-Item -ItemType Directory -Path $dest -Force
        Get-ChildItem -LiteralPath (Join-Path $work $dir) -File | Copy-Item -Destination $dest -Force
    }
    $manifest = [ordered]@{
        Inputs = $before
        BitstreamSHA256 = Get-Sha256 (Join-Path $PSScriptRoot 'generate_bitstream\hdmi_loop.sbit')
        TimingSHA256 = Get-Sha256 (Join-Path $PSScriptRoot 'report_timing\hdmi_loop.rtr')
        BuiltAtUTC = [DateTime]::UtcNow.ToString('o')
        PdsBin = $bin
        Workspace = $work
        HardwareProgrammed = $false
    }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'generate_bitstream\validated_build.json') -Encoding UTF8
    Assert-BuildManifest $PSScriptRoot
    $buildStatus.Status = 'passed'
    $buildStatus['FinishedAtUTC'] = [DateTime]::UtcNow.ToString('o')
    $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'status.json') -Encoding UTF8
    $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'latest_build.json') -Encoding UTF8
    Write-Host 'SUCCESS: current-source bitstream generated; internal timing passed.'
    Write-Host "Bitstream: $PSScriptRoot\generate_bitstream\hdmi_loop.sbit"
    Write-Host 'No hardware was accessed. External HDMI timing still requires board validation.'
} catch {
    if ($buildStatus) {
        $buildStatus.Status = 'failed'
        $buildStatus['Error'] = "$_"
        $buildStatus['FinishedAtUTC'] = [DateTime]::UtcNow.ToString('o')
        $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'status.json') -Encoding UTF8
        $buildStatus | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'latest_build.json') -Encoding UTF8
    }
    Write-Host "ERROR: $_"; exit 1
}
