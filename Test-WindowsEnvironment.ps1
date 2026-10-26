#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
    [string]$SocetDataRoot = 'E:\Socet\data',
    [string]$SocetImagesRoot = 'E:\Socet\images',
    [string]$StartSocetPath = 'C:\SOCET_SET_5.6.0\bin\start_socet.bat',
    [string]$DesktopRoot = [Environment]::GetFolderPath('Desktop'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'ortho-workflow.config.example.json'),
    [switch]$SkipConversions,
    [switch]$Force,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Modules/OrthoWorkflow.psm1') -Force

$result = [ordered]@{
    Timestamp = (Get-Date).ToString('o')
    IsWindows = Test-IsWindowsHost
    PowerShellEdition = $PSVersionTable.PSEdition
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    ProjectName = $ProjectName
    SocetDataRoot = $SocetDataRoot
    SocetImagesRoot = $SocetImagesRoot
    DesktopRoot = $DesktopRoot
    StartSocet = $null
    ConfiguredStartSocetPath = $StartSocetPath
    ConversionsExpected = (-not [bool]$SkipConversions)
    ExecutionPolicy = $null
    EffectiveExecutionPolicy = $null
    ExecutionPolicyAppearsToPermitScripts = $false
    SourceRootExists = $false
    ProjectDirectory = $null
    ProjectExists = $false
    ProjectReadable = $false
    ImagesRootExists = $false
    ImagesProjectDirectory = $null
    ImagesProjectExists = $false
    ImagesProjectReadable = $false
    LisCandidates = @()
    LisCandidateDetails = @()
    SupFiles = @()
    DemCandidates = @()
    DemCandidateDetails = @()
    DemSelectionGuidance = $null
    DesktopRootExists = $false
    DesktopWriteTest = $null
    StagingDirectory = $null
    StagingDirectoryExists = $false
    StagingConflict = $null
    ConfigurationRuleDiagnostics = @()
    UnresolvedConfigurationPlaceholders = @()
    Errors = @()
    Warnings = @()
}

try { Assert-SafeProjectName -ProjectName $ProjectName | Out-Null }
catch { $result.Errors += $_.Exception.Message }

try {
    $result.ImagesRootExists = Test-Path -LiteralPath $SocetImagesRoot -PathType Container
    if (-not $result.ImagesRootExists) { $result.Errors += "SocetImagesRoot does not exist: $SocetImagesRoot" }
    else {
        $result.ImagesProjectDirectory = Resolve-ContainedPath -Root $SocetImagesRoot -Child $ProjectName -ChildLabel 'ProjectName'
        $result.ImagesProjectExists = Test-Path -LiteralPath $result.ImagesProjectDirectory -PathType Container
        if ($result.ImagesProjectExists) {
            try { Get-ChildItem -LiteralPath $result.ImagesProjectDirectory -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null; $result.ImagesProjectReadable = $true }
            catch { $result.Errors += "SOCET images project directory is not readable: $($_.Exception.Message)" }
            $lisCandidates = @(Get-ChildItem -LiteralPath $result.ImagesProjectDirectory -File -Filter '*.lis' | Sort-Object Name)
            $result.LisCandidates = @($lisCandidates | ForEach-Object FullName)
            $result.LisCandidateDetails = @($lisCandidates | ForEach-Object { [ordered]@{ Name = $_.Name; FullName = $_.FullName; LastWriteTime = $_.LastWriteTime; Length = $_.Length; IsZeroByte = ($_.Length -le 0) } })
        }
        else { $result.Errors += "SOCET images project directory does not exist: $($result.ImagesProjectDirectory)" }
    }
}
catch { $result.Errors += $_.Exception.Message }

try {
    $command = @(Get-Command -Name $StartSocetPath -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($command) {
        $resolvedCommand = $command[0]
        $source = if ($resolvedCommand.PSObject.Properties.Name -contains 'Source') { $resolvedCommand.Source } else { $null }
        $definition = if ($resolvedCommand.PSObject.Properties.Name -contains 'Definition') { $resolvedCommand.Definition } else { $null }
        $path = if ($resolvedCommand.PSObject.Properties.Name -contains 'Path') { $resolvedCommand.Path } else { $null }
        $resolvedPath = if (-not [string]::IsNullOrWhiteSpace([string]$path)) { [string]$path } elseif (-not [string]::IsNullOrWhiteSpace([string]$definition)) { [string]$definition } else { [string]$source }
        $extension = [IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
        $isValid = (-not [string]::IsNullOrWhiteSpace($resolvedPath)) -and (@('.bat','.cmd','.exe','.com') -contains $extension) -and (Test-Path -LiteralPath $resolvedPath -PathType Leaf)
        $result.StartSocet = [ordered]@{ Found = $true; IsValid = $isValid; CommandType = $resolvedCommand.CommandType.ToString(); Source = $source; Definition = $definition; Path = $path }
        if (-not $isValid) {
            $message = "The configured SOCET launcher resolved but is not a supported existing .bat, .cmd, .exe, or .com file: $StartSocetPath"
            if ($SkipConversions) { $result.Warnings += "$message Missing launcher is nonfatal only because -SkipConversions validation mode was supplied." }
            else { $result.Errors += $message }
        }
    }
    else {
        $result.StartSocet = [ordered]@{ Found = $false; IsValid = $false; CommandType = $null; Source = $null; Definition = $null; Path = $null }
        $message = "The configured SOCET launcher could not be resolved: $StartSocetPath"
        if ($SkipConversions) { $result.Warnings += "$message Missing launcher is nonfatal only because -SkipConversions validation mode was supplied." }
        else { $result.Errors += $message }
    }
}
catch {
    $message = "Unable to resolve the configured SOCET launcher: $($_.Exception.Message)"
    if ($SkipConversions) { $result.Warnings += "$message Launcher resolution failure is nonfatal only because -SkipConversions validation mode was supplied." }
    else { $result.Errors += $message }
}

try {
    $result.ExecutionPolicy = Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }
    $result.EffectiveExecutionPolicy = Get-ExecutionPolicy
    $result.ExecutionPolicyAppearsToPermitScripts = $result.EffectiveExecutionPolicy -notin @('Restricted', 'AllSigned')
    if (-not $result.ExecutionPolicyAppearsToPermitScripts) { $result.Warnings += "Effective execution policy is $($result.EffectiveExecutionPolicy); this unsigned local script may not run." }
}
catch { $result.Errors += "Unable to read execution policy: $($_.Exception.Message)" }

try {
    $config = Import-OrthoWorkflowConfiguration -ConfigPath $ConfigPath
    $result.ConfigurationRuleDiagnostics = @($config.RuleDiagnostics)
    $result.UnresolvedConfigurationPlaceholders = @(Get-UnresolvedConfigurationItems -Configuration $config.Data)
    if ($result.UnresolvedConfigurationPlaceholders.Count -gt 0) { $result.Warnings += 'Configuration contains unresolved placeholders; real Desktop staging is blocked.' }
}
catch { $result.Errors += $_.Exception.Message }

try {
    $result.SourceRootExists = Test-Path -LiteralPath $SocetDataRoot -PathType Container
    if (-not $result.SourceRootExists) { $result.Errors += "SocetDataRoot does not exist: $SocetDataRoot" }
    else {
        $result.ProjectDirectory = Resolve-ContainedPath -Root $SocetDataRoot -Child $ProjectName -ChildLabel 'ProjectName'
        $result.ProjectExists = Test-Path -LiteralPath $result.ProjectDirectory -PathType Container
        if ($result.ProjectExists) {
            try { Get-ChildItem -LiteralPath $result.ProjectDirectory -Force -ErrorAction Stop | Select-Object -First 1 | Out-Null; $result.ProjectReadable = $true }
            catch { $result.Errors += "Project directory is not readable: $($_.Exception.Message)" }
            $result.SupFiles = @(Get-OrthoSupFiles -ProjectDirectory $result.ProjectDirectory | ForEach-Object FullName)
            $demCandidates = @(Get-ChildItem -LiteralPath $result.ProjectDirectory -File -Filter '*.dth' | Sort-Object Name)
            $result.DemCandidates = @($demCandidates | ForEach-Object FullName)
            $result.DemCandidateDetails = @($demCandidates | ForEach-Object { [ordered]@{ Name = $_.Name; FullName = $_.FullName; LastWriteTime = $_.LastWriteTime; Length = $_.Length; IsZeroByte = ($_.Length -le 0) } })
            $result.DemSelectionGuidance = $(if ($demCandidates.Count -eq 1) { 'One candidate: the workflow will select it automatically.' } elseif ($demCandidates.Count -gt 1) { 'Multiple candidates: the workflow will prompt interactively when available; otherwise it will use the latest-modified fallback and log a warning.' } else { 'No candidates: the workflow will stop.' })
        }
        else { $result.Errors += "Project directory does not exist: $($result.ProjectDirectory)" }
    }
}
catch { $result.Errors += $_.Exception.Message }

try {
    $result.DesktopRootExists = Test-Path -LiteralPath $DesktopRoot -PathType Container
    if (-not $result.DesktopRootExists) { $result.Errors += "DesktopRoot does not exist: $DesktopRoot" }
    else {
        $result.StagingDirectory = Resolve-ContainedPath -Root $DesktopRoot -Child $ProjectName -ChildLabel 'ProjectName'
        $result.StagingDirectoryExists = Test-Path -LiteralPath $result.StagingDirectory -PathType Container
        $stagingRootIsFile = (Test-Path -LiteralPath $result.StagingDirectory) -and -not $result.StagingDirectoryExists
        if ($stagingRootIsFile) {
            $result.StagingConflict = 'Exists as a file; this conflict cannot be bypassed with -Force.'
            $result.Errors += "Desktop staging path exists as a file and must not be used: $($result.StagingDirectory)"
        }
        elseif ($result.StagingDirectoryExists) {
            $result.StagingConflict = $(if ($Force) { 'Exists; -Force was supplied, but unexpected staged files/folders will still block the workflow.' } else { 'Exists; the workflow will refuse to overwrite without -Force.' })
            if (-not $Force) { $result.Errors += "Desktop staging folder already exists; rerun with -Force only after inspection: $($result.StagingDirectory)" }
        }
        else { $result.StagingConflict = 'Does not exist; the workflow may create it only after complete product validation.' }
        $testPath = Join-Path $DesktopRoot ('.ortho-workflow-desktop-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllText($testPath, 'created only by Test-WindowsEnvironment.ps1')
            $result.DesktopWriteTest = "Succeeded in temporary file: $testPath"
        }
        finally {
            if (Test-Path -LiteralPath $testPath -PathType Leaf) { Remove-Item -LiteralPath $testPath -Force }
        }
    }
}
catch { $result.Errors += "Desktop staging check failed: $($_.Exception.Message)" }

if (-not $result.IsWindows) { $result.Warnings += 'This is not Windows. No SOCET command was run; Windows-only integration results are intentionally unavailable.' }
if ($result.SupFiles.Count -eq 0 -and $result.ProjectExists) { $result.Warnings += 'No *_o.sup files were found.' }
if ($result.DemCandidates.Count -gt 1 -and $result.ProjectExists) { $result.Warnings += "Found $($result.DemCandidates.Count) .dth candidates. The workflow will prompt when interactive or use a latest-modified fallback with a warning when non-interactive." }
if ($result.DemCandidates.Count -eq 0 -and $result.ProjectExists) { $result.Warnings += 'No .dth candidates were found; the workflow will stop.' }
$nonzeroLisCandidateCount = @($result.LisCandidateDetails | Where-Object { -not $_.IsZeroByte }).Count
if ($nonzeroLisCandidateCount -eq 0 -and $result.ImagesProjectExists) { $result.Warnings += 'No nonzero .lis candidates were found in the SOCET images project directory; the workflow will stop.' }
if ($nonzeroLisCandidateCount -gt 1 -and $result.ImagesProjectExists) { $result.Warnings += 'Multiple nonzero .lis candidates were found in the SOCET images project directory; the workflow will stop rather than guess.' }

$output = [pscustomobject]$result
if ($AsJson) { $output | ConvertTo-Json -Depth 6 }
else { $output | Format-List }

if ($result.Errors.Count -gt 0) { exit 1 }
