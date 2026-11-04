param([switch]$CheckPaths, [switch]$Probe)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'tools\pds_common.ps1')
    $bin = Find-PdsBin -Executable 'cdt_cfg_shell.exe' -ProjectRoot $PSScriptRoot
    $bitstream = Join-Path $PSScriptRoot 'generate_bitstream\hdmi_loop.sbit'
    $script = Join-Path $PSScriptRoot 'program_fpga.tcl'
    if (!(Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing program_fpga.tcl.' }
    if (!(Test-Path -LiteralPath $bitstream -PathType Leaf)) { throw 'Bitstream missing. Run build_hdmi_loop.bat first.' }
    if ((Get-Item -LiteralPath $bitstream).Length -eq 0) { throw 'Bitstream is empty. Rebuild first.' }
    Write-Host "PDS tools: $bin"
    Write-Host "Project: $PSScriptRoot"
    Write-Host "Bitstream: $bitstream"
    if ($CheckPaths) { Write-Host 'Path check passed. No hardware was accessed.'; return }
    Assert-BuildManifest $PSScriptRoot
    $purpose = 'program'
    if ($Probe) { $purpose = 'probe' }
    $work = New-PdsWorkspace -Purpose $purpose
    $null = New-Item -ItemType Directory -Path (Join-Path $work 'generate_bitstream')
    $stagedBit = Join-Path $work 'generate_bitstream\hdmi_loop.sbit'
    Copy-Item -LiteralPath $bitstream -Destination $stagedBit
    $manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'generate_bitstream\validated_build.json') -Raw | ConvertFrom-Json
    if ((Get-Sha256 $stagedBit) -ne $manifest.BitstreamSHA256) { throw 'Bitstream changed while staging. Rebuild first.' }
    $sourceScript = $script
    $logName = 'program_hdmi_loop.log'
    $marker = 'PDS_PROGRAM_COMMAND_FINISHED'
    if ($Probe) {
        $sourceScript = Join-Path $PSScriptRoot 'program_preflight.tcl'
        $logName = 'program_preflight.log'
        $marker = 'PDS_PROGRAM_PATHS_OK'
    }
    $stagedScript = Join-Path $work 'run.tcl'
    Copy-Item -LiteralPath $sourceScript -Destination $stagedScript
    $log = Join-Path $work $logName
    Write-Host "PDS workspace: $work"
    try {
        Invoke-PdsTool -Executable (Join-Path $bin 'cdt_cfg_shell.exe') -Arguments @('-file', $stagedScript, '-work_dir', $work) -WorkingDirectory $work -LogPath $log
    } finally {
        if (Test-Path -LiteralPath $log) {
            Copy-Item -LiteralPath $log -Destination (Join-Path $PSScriptRoot $logName) -Force
            Get-Content -LiteralPath $log | ForEach-Object { Write-Host $_ }
        }
    }
    if ((Get-Content -LiteralPath $log -Raw) -notmatch $marker) { throw "PDS did not complete the requested script. See $logName" }
    if ($Probe) { Write-Host 'Preflight passed: PDS can read the staged bitstream. JTAG programming was not requested.' }
    else { Write-Host 'FPGA SRAM configuration command completed. See program_hdmi_loop.log.' }
} catch { Write-Host "ERROR: $_"; exit 1 }
