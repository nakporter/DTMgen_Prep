# Windows-targeted SOCET workflow helpers.  The planning, validation, and test
# functions intentionally remain usable with temporary paths on non-Windows hosts.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WorkflowVersion = '0.2.0-rc1'

function Test-IsWindowsHost {
    [CmdletBinding()]
    param()
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Assert-SafeProjectName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectName)

    if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw 'ProjectName cannot be empty.' }
    if ($ProjectName -eq '.' -or $ProjectName -eq '..') { throw "Unsafe ProjectName '$ProjectName'." }
    if ([IO.Path]::IsPathRooted($ProjectName) -or $ProjectName -match '^[A-Za-z]:[\\/]' -or $ProjectName -match '[\\/]') {
        throw "ProjectName must be a single relative folder name, not a path: '$ProjectName'."
    }
    if ($ProjectName -notmatch '^[A-Za-z0-9][A-Za-z0-9 _.-]*$' -or $ProjectName.EndsWith('.') -or $ProjectName.EndsWith(' ')) {
        throw "ProjectName '$ProjectName' contains unsupported characters. Permitted: letters, digits, spaces, underscore, hyphen, and period (not trailing)."
    }
    return $true
}

function Assert-SafeLeafName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [string]$Label = 'Name')
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq '.' -or $Name -eq '..' -or [IO.Path]::IsPathRooted($Name) -or $Name -match '^[A-Za-z]:[\\/]' -or $Name -match '[\\/]') {
        throw "Unsafe $Label '$Name'. A single relative filename/folder name is required."
    }
    return $true
}

function Assert-ExistingDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [string]$Label = 'Directory')
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Label does not exist: $Path" }
    return $true
}

function Resolve-ContainedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Child,
        [string]$ChildLabel = 'path component'
    )
    Assert-SafeLeafName -Name $Child -Label $ChildLabel | Out-Null
    $rootFull = [IO.Path]::GetFullPath($Root)
    $candidate = [IO.Path]::GetFullPath((Join-Path -Path $rootFull -ChildPath $Child))
    $prefix = $rootFull.TrimEnd([char]'/', [char]'\') + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Calculated path escapes its expected root. Root='$rootFull'; candidate='$candidate'."
    }
    return $candidate
}

function Resolve-ConfiguredWorkingDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ConfigurationValue,
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OutputProductsDirectory,
        [Parameter(Mandatory)][string]$SettingName
    )
    switch ($ConfigurationValue) {
        'ProjectDirectory' { return $ProjectDirectory }
        'OutputProductsDirectory' { return $OutputProductsDirectory }
        default { throw "Unsupported $SettingName '$ConfigurationValue'." }
    }
}

function Get-WorkflowReportContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $runId = "$stamp-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $logDirectory = Join-Path $ProjectRoot 'logs'
    $reportDirectory = Join-Path (Join-Path $ProjectRoot 'reports') $runId
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    return [pscustomobject]@{
        RunId = $runId
        LogPath = Join-Path $logDirectory "workflow-$runId.log"
        TextReportPath = Join-Path $reportDirectory 'workflow-report.txt'
        JsonReportPath = Join-Path $reportDirectory 'workflow-report.json'
    }
}

function New-WorkflowState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectName, [Parameter(Mandatory)]$ReportContext, [switch]$DryRun)
    return [pscustomobject]@{
        ScriptVersion = $script:WorkflowVersion
        ProjectName = $ProjectName
        StartTime = (Get-Date).ToString('o')
        EndTime = $null
        HostOperatingSystem = [Environment]::OSVersion.VersionString
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        PowerShellEdition = $PSVersionTable.PSEdition
        DryRun = [bool]$DryRun
        IncludeColor = $false
        OutputStructure = $null
        StructureErrors = @()
        SourceProjectDirectory = $null
        SourceImagesProjectDirectory = $null
        OutputProductsDirectory = $null
        StagingDirectory = $null
        ConfigurationPath = $null
        ConfigurationRuleDiagnostics = @()
        SupInputs = @()
        DemSelected = $null
        DemSelectedPath = $null
        DemSelectionMethod = $null
        DemCandidates = @()
        DemSelectionWarnings = @()
        Commands = @()
        ExpectedFiles = @()
        LocatedFiles = @()
        MissingFiles = @()
        ZeroByteFiles = @()
        DuplicateOrAmbiguousMatches = @()
        FilesProposedForCopy = @()
        FilesActuallyCopied = @()
        ExistingStagingConflicts = @()
        UnexpectedStagingItems = @()
        CopyPlanCanExecute = $null
        CopyPlanConflictCount = 0
        CopyPlanConflictDetails = @()
        CopyPlanBlockReasons = @()
        DuplicateDestinationDetails = @()
        ExistingStagingItems = @()
        StagingDirectoryExists = $null
        StagingDirectoryStatus = $null
        StagingValidation = $null
        FilesSkipped = @()
        Warnings = @()
        FatalErrors = @()
        FatalErrorDetails = @()
        FinalSuccess = $false
        LogPath = $ReportContext.LogPath
        TextReportPath = $ReportContext.TextReportPath
        JsonReportPath = $ReportContext.JsonReportPath
    }
}

function Write-OrthoLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][ValidateSet('INFO','WARNING','ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'o'), $Level, $Message
    Add-Content -LiteralPath $State.LogPath -Value $line -Encoding UTF8
    if ($Level -eq 'WARNING') { $State.Warnings += $Message }
    if ($Level -eq 'ERROR') { $State.FatalErrors += $Message }
    Write-Host $line
}

function New-WorkflowFailureDetail {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $invocation = $ErrorRecord.InvocationInfo
    $commandName = $null
    $invocationCommand = $null
    $scriptName = $null
    $scriptLineNumber = $null
    $offsetInLine = $null
    $positionMessage = $null
    if ($null -ne $invocation) {
        $scriptName = $invocation.ScriptName
        $scriptLineNumber = $invocation.ScriptLineNumber
        $offsetInLine = $invocation.OffsetInLine
        $positionMessage = $invocation.PositionMessage
        if ($null -ne $invocation.MyCommand) {
            if ($invocation.MyCommand.PSObject.Properties.Name -contains 'Name') {
                $commandName = $invocation.MyCommand.Name
                $invocationCommand = $commandName
            }
            else { $invocationCommand = $invocation.MyCommand.GetType().FullName }
        }
    }
    return [pscustomobject]@{
        Message = $ErrorRecord.Exception.Message
        ExceptionType = $ErrorRecord.Exception.GetType().FullName
        ScriptName = $scriptName
        ScriptLineNumber = $scriptLineNumber
        OffsetInLine = $offsetInLine
        PositionMessage = $positionMessage
        FunctionName = $commandName
        InvocationMyCommand = $invocationCommand
        InvocationScriptLineNumber = $scriptLineNumber
        InvocationOffsetInLine = $offsetInLine
        ScriptStackTrace = $ErrorRecord.ScriptStackTrace
    }
}

function Import-OrthoWorkflowConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)
    $fullPath = [IO.Path]::GetFullPath($ConfigPath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Configuration file not found: $fullPath" }
    try { $config = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json }
    catch { throw "Configuration is not valid JSON: $fullPath. $($_.Exception.Message)" }
    if ($null -eq $config.Conversion -or $null -eq $config.OutputStructure -or $null -eq $config.ProductRules) { throw 'Configuration must contain Conversion, OutputStructure, and ProductRules.' }
    Assert-ValidProductRules -ProductRules @($config.ProductRules) | Out-Null
    return [pscustomobject]@{ Path = $fullPath; Data = $config; RuleDiagnostics = @(Get-ProductRuleDiagnostics -ProductRules @($config.ProductRules)) }
}

function Get-ProductRuleDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$ProductRules)
    $diagnostics = @()
    for ($index = 0; $index -lt $ProductRules.Count; $index++) {
        $rule = $ProductRules[$index]
        $properties = if ($null -ne $rule) { @($rule.PSObject.Properties.Name) } else { @() }
        $getValue = {
            param([string]$PropertyName)
            if ($properties -contains $PropertyName) { return [string]$rule.PSObject.Properties[$PropertyName].Value }
            return '<missing>'
        }
        $diagnostics += [pscustomobject]@{
            Index = $index
            RuntimeType = if ($null -eq $rule) { '<null>' } else { $rule.GetType().FullName }
            Name = & $getValue 'Name'
            Pattern = & $getValue 'Pattern'
            Group = & $getValue 'Group'
            ExpectedCount = & $getValue 'ExpectedCount'
            SearchLocation = & $getValue 'SearchLocation'
        }
    }
    return $diagnostics
}

function Assert-ValidProductRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$ProductRules)
    $validGroups = @('Standard','Color')
    $validSearchLocations = @('ProjectDirectory','OutputProductsDirectory','ImagesProjectDirectory')
    if ($ProductRules.Count -eq 0) { throw 'Configuration ProductRules must contain at least one rule.' }
    for ($index = 0; $index -lt $ProductRules.Count; $index++) {
        $rule = $ProductRules[$index]
        $label = "ProductRules[$index]"
        if ($null -eq $rule -or -not ($rule -is [pscustomobject])) { throw "$label must be a product-rule object; metadata or container values are not valid rules." }
        $properties = @($rule.PSObject.Properties.Name)
        foreach ($requiredProperty in @('Name','Pattern','Group','ExpectedCount','SearchLocation')) {
            if ($properties -notcontains $requiredProperty) { throw "$label is missing required property '$requiredProperty'." }
        }
        if ([string]::IsNullOrWhiteSpace([string]$rule.Name)) { throw "$label has an empty Name." }
        if ([string]::IsNullOrWhiteSpace([string]$rule.Pattern)) { throw "$label has an empty Pattern." }
        if ($validGroups -notcontains [string]$rule.Group) { throw "$label has invalid Group '$($rule.Group)'." }
        if ($validSearchLocations -notcontains [string]$rule.SearchLocation) { throw "$label has invalid SearchLocation '$($rule.SearchLocation)'." }
        $expectedCount = 0
        if (-not [int]::TryParse([string]$rule.ExpectedCount, [ref]$expectedCount) -or $expectedCount -le 0) { throw "$label has invalid ExpectedCount '$($rule.ExpectedCount)'." }
        $validationPattern = ([string]$rule.Pattern).Replace('{ProjectNameRegex}', 'ProjectName').Replace('{SelectedDemBaseNameRegex}', 'SelectedDemBaseName')
        try { [void][regex]::new($validationPattern) }
        catch { throw "$label has an invalid Pattern: $($_.Exception.Message)" }
    }
    return $true
}

function Resolve-ProductRulePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rule,
        [string]$ProjectName,
        [string]$SelectedDemBaseName
    )
    $pattern = [string]$Rule.Pattern
    if ($pattern.Contains('{ProjectNameRegex}')) {
        if ([string]::IsNullOrWhiteSpace($ProjectName)) { throw "Rule '$($Rule.Name)' requires ProjectName for pattern expansion." }
        $pattern = $pattern.Replace('{ProjectNameRegex}', [regex]::Escape($ProjectName))
    }
    if ($pattern.Contains('{SelectedDemBaseNameRegex}')) {
        if ([string]::IsNullOrWhiteSpace($SelectedDemBaseName)) { throw "Rule '$($Rule.Name)' requires the selected DEM base name for pattern expansion." }
        $pattern = $pattern.Replace('{SelectedDemBaseNameRegex}', [regex]::Escape($SelectedDemBaseName))
    }
    return $pattern
}

function Get-UnresolvedConfigurationItems {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration)
    $unresolved = [System.Collections.Generic.List[string]]::new()
    $findPlaceholders = $null
    $findPlaceholders = {
        param($Value, [string]$Path)
        if ($null -eq $Value) { return }
        if ($Value -is [string]) {
            if ($Value -match '__[A-Z0-9_]+__') { $unresolved.Add("$Path = $Value") | Out-Null }
            return
        }
        if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
            $index = 0
            foreach ($entry in $Value) { & $findPlaceholders $entry "$Path[$index]"; $index++ }
            return
        }
        foreach ($property in $Value.PSObject.Properties) { & $findPlaceholders $property.Value "$Path.$($property.Name)" }
    }
    & $findPlaceholders $Configuration 'Configuration'
    return @($unresolved)
}

function Get-OrthoSupFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory)
    Assert-ExistingDirectory -Path $ProjectDirectory -Label 'Project directory' | Out-Null
    return @(Get-ChildItem -LiteralPath $ProjectDirectory -File -Filter '*_o.sup' | Sort-Object Name)
}

function Test-InteractiveSelectionAvailable {
    [CmdletBinding()]
    param()
    try {
        return ($Host.Name -ne 'ServerRemoteHost' -and $null -ne $Host.UI -and $null -ne $Host.UI.RawUI -and -not [Console]::IsInputRedirected)
    }
    catch { return $false }
}

function Select-OrthoDemFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [string]$DemName,
        [ValidateSet('Auto','Interactive','NonInteractive')][string]$SelectionMode = 'Auto',
        [scriptblock]$SelectionReader,
        [scriptblock]$ConfirmationReader
    )
    Assert-ExistingDirectory -Path $ProjectDirectory -Label 'Project directory' | Out-Null
    $allCandidates = @(Get-ChildItem -LiteralPath $ProjectDirectory -File -Filter '*.dth' | Sort-Object Name)
    $candidateDetails = @($allCandidates | ForEach-Object { [pscustomobject]@{ Name = $_.Name; FullName = $_.FullName; LastWriteTime = $_.LastWriteTime; Length = $_.Length; IsZeroByte = ($_.Length -le 0) } })
    $warnings = @()
    if ($DemName) {
        Assert-SafeLeafName -Name $DemName -Label 'DemName' | Out-Null
        if ($DemName -match '\.dth$') { throw 'DemName must be the .dth base name without the extension.' }
        $demPath = Join-Path $ProjectDirectory ($DemName + '.dth')
        if (-not (Test-Path -LiteralPath $demPath -PathType Leaf)) { throw "Explicit DemName '$DemName' does not identify an existing file: $demPath" }
        $selected = Get-Item -LiteralPath $demPath
        if ($selected.Length -le 0) { throw "Explicit DemName '$DemName' identifies a zero-byte .dth file: $demPath" }
        return [pscustomobject]@{ File = $selected; Method = 'ExplicitParameter'; Candidates = $candidateDetails; Warnings = $warnings }
    }
    if ($allCandidates.Count -eq 0) { throw "No .dth DEM candidates found in $ProjectDirectory." }
    $candidates = @($allCandidates | Where-Object { $_.Length -gt 0 })
    $zeroByteCandidates = @($allCandidates | Where-Object { $_.Length -le 0 })
    if ($zeroByteCandidates.Count -gt 0) { $warnings += "Excluded zero-byte .dth candidates: $(($zeroByteCandidates.Name -join ', '))" }
    if ($candidates.Count -eq 0) { throw "No nonzero .dth DEM candidates found in $ProjectDirectory." }
    if ($candidates.Count -eq 1) {
        return [pscustomobject]@{ File = $candidates[0]; Method = 'SingleCandidate'; Candidates = $candidateDetails; Warnings = $warnings }
    }
    $canPrompt = switch ($SelectionMode) {
        'Interactive' { $true }
        'NonInteractive' { $false }
        default { Test-InteractiveSelectionAvailable }
    }
    if ($canPrompt) {
        Write-Host 'Multiple DEM files were found:'
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            $candidate = $candidates[$index]
            Write-Host "[$($index + 1)] $($candidate.Name)"
            Write-Host "    Path: $($candidate.FullName)"
            Write-Host "    Modified: $($candidate.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))"
            Write-Host "    Size: $($candidate.Length) bytes"
        }
        while ($true) {
            $prompt = "Select the DEM to use [1-$($candidates.Count)], or C to cancel"
            $choice = if ($SelectionReader) { & $SelectionReader $prompt } else { Read-Host $prompt }
            if ($null -eq $choice) { $choice = '' }
            if ($choice.ToString().Trim().ToUpperInvariant() -eq 'C') { throw [OperationCanceledException]::new('DEM selection was cancelled by the user.') }
            $number = 0
            if (-not [int]::TryParse($choice.ToString().Trim(), [ref]$number) -or $number -lt 1 -or $number -gt $candidates.Count) {
                Write-Warning "Invalid DEM selection '$choice'. Enter a number from 1 to $($candidates.Count), or C to cancel."
                continue
            }
            $selected = $candidates[$number - 1]
            $confirmPrompt = "Use DEM '$($selected.Name)'? [Y/N]"
            $confirmation = if ($ConfirmationReader) { & $ConfirmationReader $confirmPrompt $selected } else { Read-Host $confirmPrompt }
            if ($null -ne $confirmation -and $confirmation.ToString().Trim() -match '^(Y|YES)$') {
                if (-not (Test-Path -LiteralPath $selected.FullName -PathType Leaf)) { throw "Selected DEM no longer exists: $($selected.FullName)" }
                $selected = Get-Item -LiteralPath $selected.FullName
                if ($selected.Length -le 0) { throw "Selected DEM is zero bytes: $($selected.FullName)" }
                return [pscustomobject]@{ File = $selected; Method = 'InteractiveSelection'; Candidates = $candidateDetails; Warnings = $warnings }
            }
            Write-Host 'DEM selection was not confirmed. Choose again or cancel.'
        }
    }
    $ordered = @($candidates | Sort-Object @{ Expression = { $_.LastWriteTimeUtc }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $false })
    $selected = $ordered[0]
    $tied = @($ordered | Where-Object { $_.LastWriteTimeUtc -eq $selected.LastWriteTimeUtc })
    $warnings += "Interactive DEM selection was unavailable; automatically selected the most recently modified candidate: $($selected.FullName)"
    if ($tied.Count -gt 1) { $warnings += "Latest-modified tie was resolved alphabetically by filename: $(($tied.Name -join ', '))" }
    if (-not (Test-Path -LiteralPath $selected.FullName -PathType Leaf)) { throw "Automatically selected DEM no longer exists: $($selected.FullName)" }
    $selected = Get-Item -LiteralPath $selected.FullName
    if ($selected.Length -le 0) { throw "Automatically selected DEM is zero bytes: $($selected.FullName)" }
    return [pscustomobject]@{ File = $selected; Method = 'LatestModifiedFallback'; Candidates = $candidateDetails; Warnings = $warnings }
}

function Resolve-OrthoDemFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectDirectory, [string]$DemName)
    return (Select-OrthoDemFile -ProjectDirectory $ProjectDirectory -DemName $DemName).File
}

function New-OrthoCommandSpecs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][System.IO.FileInfo[]]$SupFiles,
        [Parameter(Mandatory)][System.IO.FileInfo]$DemFile,
        [Parameter(Mandatory)][string]$OrthoWorkingDirectory,
        [Parameter(Mandatory)][string]$DemWorkingDirectory,
        [string]$StartSocetPath = 'C:\SOCET_SET_5.6.0\bin\start_socet.bat'
    )
    Assert-SafeProjectName $ProjectName | Out-Null
    $commands = @()
    foreach ($sup in $SupFiles) {
        $commands += [pscustomobject]@{
            Kind = 'ortho2isis3'; Input = $sup.Name; Program = $StartSocetPath
            Arguments = @('-single', 'ortho2isis3', $ProjectName, $sup.BaseName, ($sup.BaseName + '.cub'))
            WorkingDirectory = $OrthoWorkingDirectory; ExitCode = $null; Status = 'Planned'; Output = @(); ErrorOutput = @()
        }
    }
    $commands += [pscustomobject]@{
        Kind = 'dem2isis3'; Input = $DemFile.Name; Program = $StartSocetPath
        Arguments = @('-single', 'dem2isis3', $ProjectName, $DemFile.BaseName, ($DemFile.BaseName + '.cub'))
        WorkingDirectory = $DemWorkingDirectory; ExitCode = $null; Status = 'Planned'; Output = @(); ErrorOutput = @()
    }
    return $commands
}

function ConvertTo-DisplayCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Program,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ArgumentList = @()
    )
    $parts = @($Program)
    foreach ($argument in $ArgumentList) {
        if ($argument -match '[\s"]') { $parts += ('"' + $argument.Replace('"', '\"') + '"') } else { $parts += $argument }
    }
    return $parts -join ' '
}

function ConvertTo-CmdQuotedArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Argument)
    if ($Argument -match '[%!^&|<>()"]') { throw "Unsafe character for generated batch-file argument: '$Argument'. Use Direct execution only after Windows acceptance testing." }
    return '"' + $Argument + '"'
}

function ConvertTo-SocetCmdCall {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Command)
    $arguments = @($Command.Arguments)
    if ($arguments.Count -lt 2) { throw 'A SOCET command requires an option switch, a task name, and its data arguments.' }
    $controlArguments = @()
    $index = 0
    while ($index -lt $arguments.Count -and ([string]$arguments[$index]) -match '^-') {
        $option = [string]$arguments[$index]
        if ($option -notmatch '^-[A-Za-z0-9_-]+$') { throw "Unsafe SOCET option switch: '$option'." }
        $controlArguments += $option
        $index++
    }
    if ($controlArguments.Count -eq 0 -or $index -ge $arguments.Count) { throw 'A SOCET command requires at least one option switch followed by a task name.' }
    $task = [string]$arguments[$index]
    if ($task -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw "Unsafe SOCET task name: '$task'." }
    $controlArguments += $task
    $index++
    $dataArguments = @()
    for (; $index -lt $arguments.Count; $index++) {
        $dataArguments += ConvertTo-CmdQuotedArgument -Argument ([string]$arguments[$index])
    }
    $parts = @('call', (ConvertTo-CmdQuotedArgument -Argument ([string]$Command.Program))) + $controlArguments + $dataArguments
    return $parts -join ' '
}

function New-OrthoBatchFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Commands,
        [Parameter(Mandatory)][string]$BatchPath,
        [switch]$DryRun
    )
    $orthos = @($Commands | Where-Object { $_.Kind -eq 'ortho2isis3' })
    $lines = @('@echo off', 'setlocal EnableExtensions EnableDelayedExpansion')
    $index = 0
    foreach ($command in $orthos) {
        $lines += "echo __ORTHO_WORKFLOW_BEGIN__$index"
        $lines += ConvertTo-SocetCmdCall -Command $command
        $lines += 'set "ORTHO_WORKFLOW_EXIT=!ERRORLEVEL!"'
        $lines += "echo __ORTHO_WORKFLOW_EXIT__${index}:!ORTHO_WORKFLOW_EXIT!"
        $lines += 'if not "!ORTHO_WORKFLOW_EXIT!"=="0" exit /b !ORTHO_WORKFLOW_EXIT!'
        $index++
    }
    $lines += 'exit /b 0'
    if (-not $DryRun) {
        $parent = Split-Path -Parent $BatchPath
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        [IO.File]::WriteAllLines($BatchPath, [string[]]$lines, [Text.Encoding]::ASCII)
    }
    return [pscustomobject]@{ Path = $BatchPath; Lines = $lines; Created = (-not $DryRun) }
}

function ConvertTo-StartProcessArgumentString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Program,
        [string[]]$ArgumentList = @()
    )
    $programName = [IO.Path]::GetFileNameWithoutExtension($Program)
    if ($programName -ieq 'cmd') {
        $commandIndex = -1
        for ($index = 0; $index -lt $ArgumentList.Count; $index++) {
            if ($ArgumentList[$index] -ieq '/c') { $commandIndex = $index; break }
        }
        if ($commandIndex -ge 0) {
            if ($commandIndex -ge ($ArgumentList.Count - 1)) { throw 'CMD /c requires a command string.' }
            $prefix = @()
            if ($commandIndex -gt 0) { $prefix = @($ArgumentList[0..($commandIndex - 1)] | Where-Object { $_ -ine '/s' }) }
            $commandText = @($ArgumentList[($commandIndex + 1)..($ArgumentList.Count - 1)]) -join ' '
            if ($commandText -notmatch '^(?i:call)\s+') { $commandText = ConvertTo-CmdQuotedArgument -Argument $commandText }
            return ((@($prefix) + @('/s', '/c')) -join ' ') + ' "' + $commandText + '"'
        }
    }
    $rendered = @()
    foreach ($argument in $ArgumentList) {
        if ([string]::IsNullOrEmpty($argument)) { $rendered += '""' }
        elseif ($argument -match '[\s"]') { $rendered += ('"' + $argument.Replace('"', '\"') + '"') }
        else { $rendered += $argument }
    }
    return $rendered -join ' '
}

function Invoke-OrthoExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Program,
        [string[]]$ArgumentList = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [switch]$DryRun,
        [scriptblock]$MockCommand
    )
    $display = ConvertTo-DisplayCommand -Program $Program -ArgumentList $ArgumentList
    if ($DryRun) { return [pscustomobject]@{ Command = $display; WorkingDirectory = $WorkingDirectory; ExitCode = $null; Status = 'DryRun'; Output = @(); ErrorOutput = @(); StandardErrorLevel = 'None'; WaitedForExit = $false } }
    if ($MockCommand) {
        $mockResult = & $MockCommand $Program $ArgumentList $WorkingDirectory
        if ($null -eq $mockResult) { $mockResult = [pscustomobject]@{ ExitCode = 0; Output = @(); ErrorOutput = @() } }
        $mockErrorOutput = @($mockResult.ErrorOutput)
        return [pscustomobject]@{ Command = $display; WorkingDirectory = $WorkingDirectory; ExitCode = [int]$mockResult.ExitCode; Status = $(if ($mockResult.ExitCode -eq 0) { 'Succeeded' } else { 'Failed' }); Output = @($mockResult.Output); ErrorOutput = $mockErrorOutput; StandardErrorLevel = $(if ($mockErrorOutput.Count -eq 0) { 'None' } elseif ($mockResult.ExitCode -eq 0) { 'Warning' } else { 'Error' }); WaitedForExit = $true }
    }
    if (-not (Test-IsWindowsHost)) { throw "Windows-only external execution was blocked on this host: $display" }
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw "External command working directory does not exist: $WorkingDirectory" }
    $stdout = [IO.Path]::GetTempFileName(); $stderr = [IO.Path]::GetTempFileName()
    try {
        $processArguments = ConvertTo-StartProcessArgumentString -Program $Program -ArgumentList $ArgumentList
        $process = Start-Process -FilePath $Program -ArgumentList $processArguments -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $stdout -RedirectStandardError $stderr -NoNewWindow -Wait -PassThru
        $process.WaitForExit()
        $exitCode = [int]$process.ExitCode
        $output = @(Get-Content -LiteralPath $stdout)
        $errorOutput = @(Get-Content -LiteralPath $stderr)
        return [pscustomobject]@{ Command = $display; WorkingDirectory = $WorkingDirectory; ExitCode = $exitCode; Status = $(if ($exitCode -eq 0) { 'Succeeded' } else { 'Failed' }); Output = $output; ErrorOutput = $errorOutput; StandardErrorLevel = $(if ($errorOutput.Count -eq 0) { 'None' } elseif ($exitCode -eq 0) { 'Warning' } else { 'Error' }); WaitedForExit = $true }
    }
    finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Write-OrthoExternalResultLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)][string]$Context
    )
    $errorLines = @($Result.ErrorOutput | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($errorLines.Count -eq 0) { return }
    $level = if ([int]$Result.ExitCode -eq 0) { 'WARNING' } else { 'ERROR' }
    foreach ($line in $errorLines) {
        Write-OrthoLog -State $State -Level $level -Message "Native stderr [$Context]: $line"
    }
}

function Update-OrthoBatchResults {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$OrthoCommands, [Parameter(Mandatory)]$BatchResult)
    $seen = @{}
    foreach ($line in @($BatchResult.Output)) {
        if ($line -match '^__ORTHO_WORKFLOW_EXIT__(\d+):(\d+)$') { $seen[[int]$matches[1]] = [int]$matches[2] }
    }
    for ($i = 0; $i -lt $OrthoCommands.Count; $i++) {
        if ($seen.ContainsKey($i)) { $OrthoCommands[$i].ExitCode = $seen[$i]; $OrthoCommands[$i].Status = $(if ($seen[$i] -eq 0) { 'Succeeded' } else { 'Failed' }) }
        elseif ($BatchResult.ExitCode -eq 0) { $OrthoCommands[$i].ExitCode = 0; $OrthoCommands[$i].Status = 'Succeeded' }
        else { $OrthoCommands[$i].Status = 'NotRunOrUnknown'; $OrthoCommands[$i].ExitCode = $null }
        $OrthoCommands[$i].Output = @($BatchResult.Output)
        $OrthoCommands[$i].ErrorOutput = @($BatchResult.ErrorOutput)
    }
}

function Get-ProductRuleMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$Folder,
        [Parameter(Mandatory)][string]$Pattern
    )
    $requiredExtension = if ($Rule.PSObject.Properties.Name -contains 'RequiredExtension') { $Rule.RequiredExtension } else { $null }
    $results = @()
    if (-not (Test-Path -LiteralPath $Folder -PathType Container)) { return $results }
    foreach ($file in @(Get-ChildItem -LiteralPath $Folder -File | Sort-Object Name)) {
        if ($file.Name -notmatch $Pattern) { continue }
        if (-not [string]::IsNullOrWhiteSpace($requiredExtension) -and $file.Extension -ine $requiredExtension) { continue }
        $captures = [ordered]@{}
        foreach ($key in $Matches.Keys) { if ($key -is [string]) { $captures[$key] = $Matches[$key] } }
        $results += [pscustomobject]@{ File = $file; Captures = [pscustomobject]$captures }
    }
    return $results
}

function Get-GenericProductStructureErrors {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Located
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $standardRaw = @($Located | Where-Object Role -eq 'StandardOrthoRaw')
    $standardSh = @($Located | Where-Object Role -eq 'StandardOrthoSh')
    $colorRaw = @($Located | Where-Object Role -eq 'ColorRaw')
    $colorSh = @($Located | Where-Object Role -eq 'ColorSh')
    if (($standardRaw.Count + $standardSh.Count + $colorRaw.Count + $colorSh.Count) -eq 0) { return @() }
    function Get-CaptureKey($Item, [string[]]$Names) {
        $values = @()
        foreach ($name in $Names) {
            if ($Item.Captures.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace($Item.Captures.$name)) { return $null }
            $values += $Item.Captures.$name
        }
        return $values -join [char]31
    }
    function Get-RoleKeyMap($Items, [string[]]$Names, [string]$Label) {
        $map = @{}
        foreach ($item in $Items) {
            $key = Get-CaptureKey $item $Names
            if ($null -eq $key) { $errors.Add("$Label has missing required capture values: $($item.Name)") | Out-Null; continue }
            if (-not $map.ContainsKey($key)) { $map[$key] = [System.Collections.Generic.List[object]]::new() }
            [void]$map[$key].Add($item)
        }
        return $map
    }
    if (($standardRaw.Count + $standardSh.Count) -gt 0) {
        $standardRawMap = Get-RoleKeyMap $standardRaw @('ImageId','Level') 'Standard RAW'
        $standardShMap = Get-RoleKeyMap $standardSh @('ImageId','Level') 'Standard SH'
        foreach ($key in @($standardRawMap.Keys + $standardShMap.Keys | Sort-Object -Unique)) {
            $standardRawCount = if ($standardRawMap.ContainsKey($key)) { $standardRawMap[$key].Count } else { 0 }
            $standardShCount = if ($standardShMap.ContainsKey($key)) { $standardShMap[$key].Count } else { 0 }
            if ($standardRawCount -ne 1 -or $standardShCount -ne 1) { $errors.Add("Standard RAW/SH pair mismatch for captured key '$key'.") | Out-Null }
        }
        $standardImages = @($standardRaw | ForEach-Object { $_.Captures.ImageId } | Sort-Object -Unique)
        if ($standardImages.Count -ne 2) { $errors.Add("Expected exactly two standard stereo image groups; found $($standardImages.Count).") | Out-Null }
        foreach ($image in $standardImages) {
            $levels = @($standardRaw | Where-Object { $_.Captures.ImageId -eq $image } | ForEach-Object { $_.Captures.Level } | Sort-Object -Unique)
            if ($levels.Count -ne 2) { $errors.Add("Standard image group '$image' must have exactly two ortho levels; found $($levels.Count).") | Out-Null }
        }
    }
    if (($colorRaw.Count + $colorSh.Count) -gt 0) {
        $colorRawMap = Get-RoleKeyMap $colorRaw @('ImageId','Channel','Level') 'COLOR RAW'
        $colorShMap = Get-RoleKeyMap $colorSh @('ImageId','Channel','Level') 'COLOR SH'
        foreach ($key in @($colorRawMap.Keys + $colorShMap.Keys | Sort-Object -Unique)) {
            $colorRawCount = if ($colorRawMap.ContainsKey($key)) { $colorRawMap[$key].Count } else { 0 }
            $colorShCount = if ($colorShMap.ContainsKey($key)) { $colorShMap[$key].Count } else { 0 }
            if ($colorRawCount -ne 1 -or $colorShCount -ne 1) { $errors.Add("COLOR RAW/SH pair mismatch for captured key '$key'.") | Out-Null }
        }
        $colorImages = @($colorRaw | ForEach-Object { $_.Captures.ImageId } | Sort-Object -Unique)
        if ($colorImages.Count -ne 2) { $errors.Add("Expected exactly two COLOR stereo image groups; found $($colorImages.Count).") | Out-Null }
        foreach ($image in $colorImages) {
            $channels = @($colorRaw | Where-Object { $_.Captures.ImageId -eq $image } | ForEach-Object { $_.Captures.Channel } | Sort-Object -Unique)
            $channelDifferences = @(Compare-Object -ReferenceObject @('BG','IR','RED') -DifferenceObject $channels)
            if ($channelDifferences.Count -ne 0) { $errors.Add("COLOR image group '$image' must contain exactly BG, IR, and RED channels.") | Out-Null }
            foreach ($channel in @('BG','IR','RED')) {
                $levels = @($colorRaw | Where-Object { $_.Captures.ImageId -eq $image -and $_.Captures.Channel -eq $channel } | ForEach-Object { $_.Captures.Level } | Sort-Object -Unique)
                if ($levels.Count -ne 2) { $errors.Add("COLOR image/channel '$image/$channel' must have exactly two levels; found $($levels.Count).") | Out-Null }
            }
        }
    }
    return $errors.ToArray()
}

function Add-ProductRuleMatchName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$MatchMap,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][AllowEmptyString()][string]$RuleName
    )
    if ([string]::IsNullOrWhiteSpace($RuleName)) { throw "Product-match bookkeeping rejected a null or blank rule name for '$Path'." }
    if (-not $MatchMap.ContainsKey($Path)) { $MatchMap[$Path] = [System.Collections.Generic.List[string]]::new() }
    [void]$MatchMap[$Path].Add($RuleName.Trim())
}

function Get-ProductRuleMatchAmbiguities {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$MatchMap)
    $ambiguities = @()
    foreach ($entry in $MatchMap.GetEnumerator()) {
        if ($null -eq $entry.Value) { throw "Product-match bookkeeping rejected a null match list for '$($entry.Key)'." }
        $matchNames = @($entry.Value.ToArray())
        $blankNames = @($matchNames | Where-Object { [string]::IsNullOrWhiteSpace($_) })
        if ($blankNames.Count -gt 0) { throw "Product-match bookkeeping rejected a null or blank rule name for '$($entry.Key)'." }
        $distinctNames = @($matchNames | Sort-Object -Unique)
        if ($distinctNames.Count -ge 2) { $ambiguities += "File matched multiple rules: $($entry.Key) => $($distinctNames -join ', ')" }
    }
    return $ambiguities
}

function Get-ProductValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectDirectory,
        [Parameter(Mandatory)][string]$OutputProductsDirectory,
        [Parameter(Mandatory)]$Configuration,
        [string]$ImagesProjectDirectory,
        [string]$ProjectName,
        [string]$SelectedDemBaseName,
        [switch]$IncludeColor
    )
    Assert-ValidProductRules -ProductRules @($Configuration.ProductRules) | Out-Null
    $runtimeRuleDiagnostics = @(Get-ProductRuleDiagnostics -ProductRules @($Configuration.ProductRules))
    foreach ($diagnostic in $runtimeRuleDiagnostics) {
        if ([string]::IsNullOrWhiteSpace($diagnostic.Name) -or $diagnostic.Name -eq '<missing>') {
            throw "Runtime product-rule guard rejected ProductRules[$($diagnostic.Index)] with Name='$($diagnostic.Name)', Pattern='$($diagnostic.Pattern)', Group='$($diagnostic.Group)', ExpectedCount='$($diagnostic.ExpectedCount)', SearchLocation='$($diagnostic.SearchLocation)', Type='$($diagnostic.RuntimeType)'."
        }
    }
    $locations = @{ ProjectDirectory = $ProjectDirectory; OutputProductsDirectory = $OutputProductsDirectory; ImagesProjectDirectory = $ImagesProjectDirectory }
    $rules = @($Configuration.ProductRules | Where-Object {
        $enabled = if ($_.PSObject.Properties.Name -contains 'Enabled') { $_.Enabled -ne $false } else { $true }
        $enabled -and (($IncludeColor -and $_.Group -in @('Standard','Color')) -or (-not $IncludeColor -and $_.Group -eq 'Standard'))
    })
    $expected = @(); $located = @(); $missing = @(); $zero = @(); $ambiguous = @(); $selected = @(); $allMatches = @{}
    foreach ($rule in $rules) {
        if ($null -eq $locations[$rule.SearchLocation]) { throw "Rule '$($rule.Name)' has unsupported SearchLocation '$($rule.SearchLocation)'." }
        $folder = $locations[$rule.SearchLocation]
        $pattern = Resolve-ProductRulePattern -Rule $rule -ProjectName $ProjectName -SelectedDemBaseName $SelectedDemBaseName
        $matches = @(Get-ProductRuleMatches -Rule $rule -Folder $folder -Pattern $pattern)
        $candidateMatches = @(if ($rule.PSObject.Properties.Name -contains 'NonZeroCandidatesOnly' -and $rule.NonZeroCandidatesOnly -eq $true) { $matches | Where-Object { $_.File.Length -gt 0 } } else { $matches })
        $role = if ($rule.PSObject.Properties.Name -contains 'Role') { $rule.Role } else { $rule.Name }
        $expected += [pscustomobject]@{ Rule = $rule.Name; Role = $role; Pattern = $pattern; ExpectedCount = [int]$rule.ExpectedCount; SearchLocation = $rule.SearchLocation; Group = $rule.Group }
        foreach ($match in $candidateMatches) { Add-ProductRuleMatchName -MatchMap $allMatches -Path $match.File.FullName -RuleName $rule.Name }
        if ($candidateMatches.Count -lt [int]$rule.ExpectedCount) { $missing += "$($rule.Name): expected $($rule.ExpectedCount), found $($candidateMatches.Count)" }
        if ($candidateMatches.Count -gt [int]$rule.ExpectedCount) { $ambiguous += "$($rule.Name): expected $($rule.ExpectedCount), found $($candidateMatches.Count): $(($candidateMatches.File.FullName -join ', '))" }
        foreach ($match in $candidateMatches) {
            $file = $match.File
            $located += [pscustomobject]@{ Rule = $rule.Name; Role = $role; Path = $file.FullName; Name = $file.Name; Length = $file.Length; Group = $rule.Group; Captures = $match.Captures }
            if ($file.Length -le 0) { $zero += "$($rule.Name): $($file.FullName)" }
        }
        if ($candidateMatches.Count -eq [int]$rule.ExpectedCount) {
            foreach ($match in $candidateMatches) { $selected += [pscustomobject]@{ File = $match.File; Group = $rule.Group; Rule = $rule.Name; Role = $role; Captures = $match.Captures } }
        }
    }
    $ambiguous += @(Get-ProductRuleMatchAmbiguities -MatchMap $allMatches)
    $structureErrors = @(Get-GenericProductStructureErrors -Located $located); $structure = $null
    if ($Configuration.PSObject.Properties.Name -contains 'OutputStructure') {
        $mainFiles = @($selected | Where-Object Group -eq 'Standard' | ForEach-Object File)
        $colorFiles = @($selected | Where-Object Group -eq 'Color' | ForEach-Object File)
        $main = $Configuration.OutputStructure.MainFolder
        $color = $Configuration.OutputStructure.ColorFolder
        $mainSummary = [pscustomobject]@{
            ExpectedFileCount = [int]$main.ExpectedFileCount; ActualFileCount = $mainFiles.Count
            ExpectedDirectoryCount = [int]$main.ExpectedDirectoryCount; ActualDirectoryCount = $(if ($Configuration.OutputStructure.RequireColorDirectory -and $IncludeColor) { 1 } else { 0 })
            ExpectedRawCount = [int]$main.ExpectedRawCount; ActualRawCount = @($mainFiles | Where-Object Name -match '\.raw$').Count
            ExpectedShellScriptCount = [int]$main.ExpectedShellScriptCount; ActualShellScriptCount = @($mainFiles | Where-Object Name -match '\.sh$').Count
            ExpectedReportCount = [int]$main.ExpectedReportCount; ActualReportCount = @($mainFiles | Where-Object Name -match '\.rep$').Count
            ExpectedPngCount = [int]$main.ExpectedPngCount; ActualPngCount = @($mainFiles | Where-Object Name -match '\.png$').Count
            ExpectedGnuCount = [int]$main.ExpectedGnuCount; ActualGnuCount = @($mainFiles | Where-Object Name -match '\.gnu$').Count
            ExpectedLisCount = [int]$main.ExpectedLisCount; ActualLisCount = @($mainFiles | Where-Object { $_ -match 'statistics\.lis$' }).Count
        }
        $colorSummary = [pscustomobject]@{
            ExpectedFileCount = [int]$color.ExpectedFileCount; ActualFileCount = $colorFiles.Count
            ExpectedRawCount = [int]$color.ExpectedRawCount; ActualRawCount = @($colorFiles | Where-Object Name -match '\.raw$').Count
            ExpectedShellScriptCount = [int]$color.ExpectedShellScriptCount; ActualShellScriptCount = @($colorFiles | Where-Object Name -match '\.sh$').Count
        }
        $structure = [pscustomobject]@{ RequireColorDirectory = [bool]$Configuration.OutputStructure.RequireColorDirectory; MainFolder = $mainSummary; ColorFolder = $colorSummary }
        foreach ($property in @('FileCount','DirectoryCount','RawCount','ShellScriptCount','ReportCount','PngCount','GnuCount','LisCount')) {
            if ($mainSummary."Expected$property" -ne $mainSummary."Actual$property") { $structureErrors += "Main folder ${property}: expected $($mainSummary."Expected$property"), found $($mainSummary."Actual$property")." }
        }
        if ($structure.RequireColorDirectory -and -not $IncludeColor) { $structureErrors += 'COLOR directory is required by OutputStructure; run with -IncludeColor.' }
        if ($IncludeColor) {
            foreach ($property in @('FileCount','RawCount','ShellScriptCount')) {
                if ($colorSummary."Expected$property" -ne $colorSummary."Actual$property") { $structureErrors += "COLOR folder ${property}: expected $($colorSummary."Expected$property"), found $($colorSummary."Actual$property")." }
            }
        }
    }
    return [pscustomobject]@{ Expected = $expected; Located = $located; Missing = $missing; ZeroByte = $zero; Ambiguous = $ambiguous; Structure = $structure; StructureErrors = $structureErrors; SelectedFiles = @($selected | Sort-Object { $_.File.FullName }); IsValid = (($missing.Count -eq 0) -and ($zero.Count -eq 0) -and ($ambiguous.Count -eq 0) -and ($structureErrors.Count -eq 0)) }
}

function New-ProductCopyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ProductValidation,
        [Parameter(Mandatory)][string]$StagingDirectory,
        [switch]$Force
    )
    $items = @(); $duplicates = @{}
    $stagingRootExists = Test-Path -LiteralPath $StagingDirectory
    $stagingDirectoryExists = Test-Path -LiteralPath $StagingDirectory -PathType Container
    $stagingRootIsFile = $stagingRootExists -and -not $stagingDirectoryExists
    $existingRootItems = @(
        if ($stagingDirectoryExists) {
            Get-ChildItem -LiteralPath $StagingDirectory -Force
        }
    )
    $existingStagingItems = @(
        if ($stagingDirectoryExists) {
            Get-ChildItem -LiteralPath $StagingDirectory -Force -Recurse
        }
    )
    foreach ($selectedFile in $ProductValidation.SelectedFiles) {
        $file = $selectedFile.File
        $isColor = $selectedFile.Group -eq 'Color'
        $targetFolder = if ($isColor) { Join-Path $StagingDirectory 'COLOR' } else { $StagingDirectory }
        $target = Join-Path $targetFolder $file.Name
        $destinationExists = Test-Path -LiteralPath $target
        $destinationItemType = 'Absent'
        if ($destinationExists) {
            $destinationItem = Get-Item -LiteralPath $target
            $destinationItemType = if ($destinationItem.PSIsContainer) { 'Directory' } else { 'File' }
        }
        $items += [pscustomobject]@{
            Source = $file.FullName
            StagingPath = $target
            ProductRule = $selectedFile.Rule
            Group = $(if ($isColor) {'Color'} else {'Standard'})
            Action = 'Copy'
            DestinationAlreadyExists = [bool]$destinationExists
            DestinationItemType = $destinationItemType
            DuplicateTarget = $false
            DuplicateSources = @()
            ConflictReason = $null
        }
        if (-not $duplicates.ContainsKey($target)) { $duplicates[$target] = [System.Collections.Generic.List[string]]::new() }
        [void]$duplicates[$target].Add($file.FullName)
    }
    $unexpectedStagingItems = @()
    if ($stagingDirectoryExists) {
        $expectedStagingPaths = @{}
        foreach ($item in $items) { $expectedStagingPaths[$item.StagingPath] = $true }
        $colorDirectory = Join-Path $StagingDirectory 'COLOR'
        $hasColorProducts = @($items | Where-Object Group -eq 'Color').Count -gt 0
        foreach ($entry in $existingRootItems) {
            if ($entry.PSIsContainer -and $entry.FullName -eq $colorDirectory -and $hasColorProducts) {
                foreach ($colorEntry in @(Get-ChildItem -LiteralPath $colorDirectory -Force -Recurse)) {
                    if ($colorEntry.PSIsContainer -or -not $expectedStagingPaths.ContainsKey($colorEntry.FullName)) { $unexpectedStagingItems += $colorEntry.FullName }
                }
            }
            elseif (-not $expectedStagingPaths.ContainsKey($entry.FullName)) { $unexpectedStagingItems += $entry.FullName }
        }
    }
    $duplicateDestinationDetails = @()
    foreach ($entry in $duplicates.GetEnumerator()) {
        $sources = @($entry.Value.ToArray())
        if ($sources.Count -gt 1) { $duplicateDestinationDetails += [pscustomobject]@{ DestinationPath = $entry.Key; SourcePaths = $sources; ConflictType = 'DuplicateDestination' } }
    }
    $conflictDetails = @()
    if ($stagingRootIsFile) {
        $conflictDetails += [pscustomobject]@{
            SourcePath = $null
            DestinationPath = $StagingDirectory
            ProductRule = $null
            Group = $null
            ConflictType = 'StagingRootIsFile'
            DestinationAlreadyExists = $true
            DestinationItemType = 'File'
            DuplicateTarget = $false
            DuplicateSources = @()
        }
    }
    foreach ($item in $items) {
        $reasons = @()
        if ($item.DestinationAlreadyExists) {
            $reasons += $(if ($item.DestinationItemType -eq 'Directory') { 'DestinationDirectoryExists' } else { 'DestinationFileExists' })
        }
        $duplicateDetail = @($duplicateDestinationDetails | Where-Object DestinationPath -eq $item.StagingPath)
        if ($duplicateDetail.Count -eq 1) {
            $item.DuplicateTarget = $true
            $item.DuplicateSources = @($duplicateDetail[0].SourcePaths)
            $reasons += 'DuplicateDestination'
        }
        if ($reasons.Count -gt 0) {
            $item.ConflictReason = $reasons -join '; '
            $conflictDetails += [pscustomobject]@{
                SourcePath = $item.Source
                DestinationPath = $item.StagingPath
                ProductRule = $item.ProductRule
                Group = $item.Group
                ConflictType = $item.ConflictReason
                DestinationAlreadyExists = $item.DestinationAlreadyExists
                DestinationItemType = $item.DestinationItemType
                DuplicateTarget = $item.DuplicateTarget
                DuplicateSources = @($item.DuplicateSources)
            }
        }
    }
    foreach ($path in @($unexpectedStagingItems | Sort-Object -Unique)) {
        $entry = Get-Item -LiteralPath $path
        $conflictDetails += [pscustomobject]@{
            SourcePath = $null
            DestinationPath = $path
            ProductRule = $null
            Group = $null
            ConflictType = 'UnexpectedStagingItem'
            DestinationAlreadyExists = $true
            DestinationItemType = $(if ($entry.PSIsContainer) { 'Directory' } else { 'File' })
            DuplicateTarget = $false
            DuplicateSources = @()
        }
    }
    $existingConflicts = @($items | Where-Object DestinationAlreadyExists | ForEach-Object StagingPath | Sort-Object -Unique)
    $duplicateTargets = @($duplicateDestinationDetails | ForEach-Object { "Multiple source files target $($_.DestinationPath): $($_.SourcePaths -join ', ')" })
    $stagingDirectoryStatus = if ($stagingRootIsFile) { 'ExistsAsFile' } elseif (-not $stagingDirectoryExists) { 'Absent' } elseif ($existingStagingItems.Count -eq 0) { 'ExistsEmpty' } elseif ($unexpectedStagingItems.Count -eq 0) { 'ExistsContainsOnlyExpectedItems' } else { 'ExistsWithUnexpectedItems' }
    $directoryDestinationConflictCount = @($items | Where-Object { $_.DestinationAlreadyExists -and $_.DestinationItemType -eq 'Directory' }).Count
    $blockReasons = @()
    if (-not $ProductValidation.IsValid) { $blockReasons += 'ProductValidationInvalid' }
    if ($stagingRootIsFile) { $blockReasons += 'StagingRootIsFile' }
    if (-not $Force -and $existingConflicts.Count -gt 0) { $blockReasons += 'ExistingDestinationWithoutForce' }
    if ($directoryDestinationConflictCount -gt 0) { $blockReasons += 'DestinationDirectoryConflict' }
    if ($duplicateDestinationDetails.Count -gt 0) { $blockReasons += 'DuplicateDestination' }
    if ($unexpectedStagingItems.Count -gt 0) { $blockReasons += 'UnexpectedStagingItems' }
    $canExecute = ($blockReasons.Count -eq 0)
    return [pscustomobject]@{
        Items = $items
        ExistingConflicts = $existingConflicts
        DuplicateTargets = $duplicateTargets
        DuplicateDestinationDetails = $duplicateDestinationDetails
        ExistingStagingItems = @($existingStagingItems | ForEach-Object { [pscustomobject]@{ Path = $_.FullName; ItemType = $(if ($_.PSIsContainer) { 'Directory' } else { 'File' }) } })
        UnexpectedStagingItems = @($unexpectedStagingItems | Sort-Object -Unique)
        ConflictDetails = $conflictDetails
        BlockReasons = $blockReasons
        StagingDirectoryExists = [bool]$stagingDirectoryExists
        StagingDirectoryStatus = $stagingDirectoryStatus
        CanExecute = $canExecute
    }
}

function Invoke-CommandSpec {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Command,
        [switch]$DryRun,
        [scriptblock]$MockCommand,
        [switch]$UseCmdCall,
        [string]$CommandInterpreter = $env:ComSpec
    )
    if ($UseCmdCall) {
        if ([string]::IsNullOrWhiteSpace($CommandInterpreter)) { throw 'ComSpec is unavailable; cannot invoke the SOCET batch launcher with CMD call.' }
        $cmdLine = ConvertTo-SocetCmdCall -Command $Command
        $result = Invoke-OrthoExternalCommand -Program $CommandInterpreter -ArgumentList @('/d', '/c', $cmdLine) -WorkingDirectory $Command.WorkingDirectory -DryRun:$DryRun -MockCommand $MockCommand
    }
    else {
        $result = Invoke-OrthoExternalCommand -Program $Command.Program -ArgumentList $Command.Arguments -WorkingDirectory $Command.WorkingDirectory -DryRun:$DryRun -MockCommand $MockCommand
    }
    $Command.ExitCode = $result.ExitCode
    $Command.Status = $result.Status
    $Command.Output = $result.Output
    $Command.ErrorOutput = $result.ErrorOutput
    return $result
}

function Invoke-ProductCopyPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$CopyPlan, [switch]$DryRun, [switch]$Force)
    if (-not $CopyPlan.CanExecute) { throw 'Copy plan is unsafe or incomplete; no files were copied.' }
    $copied = @(); $skipped = @()
    foreach ($item in $CopyPlan.Items) {
        if ($DryRun) { $skipped += "$($item.Source) => $($item.StagingPath) (DryRun)"; continue }
        $folder = Split-Path -Parent $item.StagingPath
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        if ((Test-Path -LiteralPath $item.StagingPath -PathType Leaf) -and -not $Force) { throw "Staging file exists and -Force was not supplied: $($item.StagingPath)" }
        Copy-Item -LiteralPath $item.Source -Destination $item.StagingPath -Force:$Force
        $copied += "$($item.Source) => $($item.StagingPath)"
    }
    return [pscustomobject]@{ Copied = $copied; Skipped = $skipped }
}

function Test-StagedProductSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$CopyPlan,
        [Parameter(Mandatory)][string]$StagingDirectory,
        [Parameter(Mandatory)]$OutputStructure,
        [string]$AdditionalExpectedMainFile
    )

    $missing = @()
    $zeroByte = @()
    $unexpected = @()
    $filenameMismatches = @()
    $structureErrors = @()

    if (-not (Test-Path -LiteralPath $StagingDirectory -PathType Container)) {
        return [pscustomobject]@{
            IsValid = $false
            Status = 'MissingStagingDirectory'
            Missing = @($StagingDirectory)
            ZeroByte = @()
            Unexpected = @()
            FilenameMismatches = @()
            StructureErrors = @('Staging directory does not exist.')
            MainFolder = $null
            ColorFolder = $null
        }
    }

    $expectedPaths = @{}

    foreach ($item in $CopyPlan.Items) {
        $expectedPaths[$item.StagingPath] = $item

        if (-not (Test-Path -LiteralPath $item.StagingPath -PathType Leaf)) {
            $missing += $item.StagingPath
            continue
        }

        $staged = Get-Item -LiteralPath $item.StagingPath

        if ($staged.Length -le 0) {
            $zeroByte += $item.StagingPath
        }

        if ((Split-Path -Leaf $item.Source) -ne (Split-Path -Leaf $item.StagingPath)) {
            $filenameMismatches += "$($item.Source) => $($item.StagingPath)"
        }
    }

    $additionalMainFileCount = 0

    if (-not [string]::IsNullOrWhiteSpace($AdditionalExpectedMainFile)) {
        $additionalMainFileCount = 1
        $expectedPaths[$AdditionalExpectedMainFile] = $null

        if (-not (Test-Path -LiteralPath $AdditionalExpectedMainFile -PathType Leaf)) {
            $missing += $AdditionalExpectedMainFile
        }
        else {
            $additionalFile = Get-Item -LiteralPath $AdditionalExpectedMainFile

            if ($additionalFile.Length -le 0) {
                $zeroByte += $AdditionalExpectedMainFile
            }
        }
    }

    $colorDirectory = Join-Path $StagingDirectory 'COLOR'
    $hasColorProducts = @($CopyPlan.Items | Where-Object Group -eq 'Color').Count -gt 0

    foreach ($entry in @(Get-ChildItem -LiteralPath $StagingDirectory -Force)) {
        if ($entry.PSIsContainer -and $entry.FullName -eq $colorDirectory -and $hasColorProducts) {
            foreach ($colorEntry in @(Get-ChildItem -LiteralPath $colorDirectory -Force -Recurse)) {
                if ($colorEntry.PSIsContainer -or -not $expectedPaths.ContainsKey($colorEntry.FullName)) {
                    $unexpected += $colorEntry.FullName
                }
            }
        }
        elseif (-not $expectedPaths.ContainsKey($entry.FullName)) {
            $unexpected += $entry.FullName
        }
    }

    if ($hasColorProducts -and -not (Test-Path -LiteralPath $colorDirectory -PathType Container)) {
        $structureErrors += 'Required COLOR staging directory does not exist.'
    }

    $mainFiles = @(Get-ChildItem -LiteralPath $StagingDirectory -File -Force)

    $productMainFiles = @(
        $mainFiles | Where-Object {
            [string]::IsNullOrWhiteSpace($AdditionalExpectedMainFile) -or
            $_.FullName -ne $AdditionalExpectedMainFile
        }
    )

    $colorFiles = @(
        if (Test-Path -LiteralPath $colorDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $colorDirectory -File -Force
        }
    )

    $mainSummary = [pscustomobject]@{
        ExpectedFileCount = [int]$OutputStructure.MainFolder.ExpectedFileCount + $additionalMainFileCount
        ActualFileCount = $mainFiles.Count

        ExpectedDirectoryCount = [int]$OutputStructure.MainFolder.ExpectedDirectoryCount
        ActualDirectoryCount = @((Get-ChildItem -LiteralPath $StagingDirectory -Directory -Force)).Count

        ExpectedRawCount = [int]$OutputStructure.MainFolder.ExpectedRawCount
        ActualRawCount = @($productMainFiles | Where-Object Name -match '\.raw$').Count

        ExpectedShellScriptCount = [int]$OutputStructure.MainFolder.ExpectedShellScriptCount
        ActualShellScriptCount = @($productMainFiles | Where-Object Name -match '\.sh$').Count

        ExpectedReportCount = [int]$OutputStructure.MainFolder.ExpectedReportCount
        ActualReportCount = @($productMainFiles | Where-Object Name -match '\.rep$').Count

        ExpectedPngCount = [int]$OutputStructure.MainFolder.ExpectedPngCount
        ActualPngCount = @($productMainFiles | Where-Object Name -match '\.png$').Count

        ExpectedGnuCount = [int]$OutputStructure.MainFolder.ExpectedGnuCount
        ActualGnuCount = @($productMainFiles | Where-Object Name -match '\.gnu$').Count

        ExpectedLisCount = [int]$OutputStructure.MainFolder.ExpectedLisCount
        ActualLisCount = @($productMainFiles | Where-Object { $_ -match 'statistics\.lis$' }).Count
    }

    $colorSummary = [pscustomobject]@{
        ExpectedFileCount = [int]$OutputStructure.ColorFolder.ExpectedFileCount
        ActualFileCount = $colorFiles.Count

        ExpectedRawCount = [int]$OutputStructure.ColorFolder.ExpectedRawCount
        ActualRawCount = @($colorFiles | Where-Object Name -match '\.raw$').Count

        ExpectedShellScriptCount = [int]$OutputStructure.ColorFolder.ExpectedShellScriptCount
        ActualShellScriptCount = @($colorFiles | Where-Object Name -match '\.sh$').Count
    }

    foreach ($property in @(
        'FileCount',
        'DirectoryCount',
        'RawCount',
        'ShellScriptCount',
        'ReportCount',
        'PngCount',
        'GnuCount',
        'LisCount'
    )) {
        if ($mainSummary."Expected$property" -ne $mainSummary."Actual$property") {
            $structureErrors += "Staged main folder ${property}: expected $($mainSummary."Expected$property"), found $($mainSummary."Actual$property")."
        }
    }

    foreach ($property in @('FileCount','RawCount','ShellScriptCount')) {
        if ($colorSummary."Expected$property" -ne $colorSummary."Actual$property") {
            $structureErrors += "Staged COLOR folder ${property}: expected $($colorSummary."Expected$property"), found $($colorSummary."Actual$property")."
        }
    }

    return [pscustomobject]@{
        IsValid = (
            ($missing.Count -eq 0) -and
            ($zeroByte.Count -eq 0) -and
            ($unexpected.Count -eq 0) -and
            ($filenameMismatches.Count -eq 0) -and
            ($structureErrors.Count -eq 0)
        )
        Status = 'Validated'
        Missing = $missing
        ZeroByte = $zeroByte
        Unexpected = @($unexpected | Sort-Object -Unique)
        FilenameMismatches = $filenameMismatches
        StructureErrors = $structureErrors
        MainFolder = $mainSummary
        ColorFolder = $colorSummary
    }
}

function Get-ReportPropertyValue {
    [CmdletBinding()]
    param($InputObject, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-ReportStringArray {
    [CmdletBinding()]
    param($Value)
    $result = @()
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [IO.FileSystemInfo]) { $result += [string]$item.FullName }
        elseif ($item -is [Exception]) { $result += [string]$item.Message }
        elseif ($item -is [System.Management.Automation.ErrorRecord]) { $result += [string]$item.Exception.Message }
        else { $result += [string]$item }
    }
    return $result
}

function ConvertTo-ReportDateString {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.ToString('o') }
    return [string]$Value
}

function ConvertTo-ReportCaptureData {
    [CmdletBinding()]
    param($Captures)
    if ($null -eq $Captures) { return $null }
    $plain = [ordered]@{}
    foreach ($property in @($Captures.PSObject.Properties | Sort-Object Name)) {
        $plain[$property.Name] = if ($null -eq $property.Value) { $null } else { [string]$property.Value }
    }
    return $plain
}

function ConvertTo-ReportFileData {
    [CmdletBinding()]
    param($Value)
    if ($null -eq $Value) { return $null }
    $fullName = Get-ReportPropertyValue $Value 'FullName' (Get-ReportPropertyValue $Value 'Path' $null)
    $name = Get-ReportPropertyValue $Value 'Name' $null
    if ([string]::IsNullOrWhiteSpace([string]$name) -and -not [string]::IsNullOrWhiteSpace([string]$fullName)) { $name = Split-Path -Leaf ([string]$fullName) }
    $length = Get-ReportPropertyValue $Value 'Length' $null
    $lastWriteTime = Get-ReportPropertyValue $Value 'LastWriteTime' $null
    return [ordered]@{
        FullName = if ($null -eq $fullName) { $null } else { [string]$fullName }
        Name = if ($null -eq $name) { $null } else { [string]$name }
        Length = if ($null -eq $length) { $null } else { [long]$length }
        LastWriteTime = ConvertTo-ReportDateString $lastWriteTime
        Rule = [string](Get-ReportPropertyValue $Value 'Rule' '')
        Role = [string](Get-ReportPropertyValue $Value 'Role' '')
        Group = [string](Get-ReportPropertyValue $Value 'Group' '')
        Captures = ConvertTo-ReportCaptureData (Get-ReportPropertyValue $Value 'Captures' $null)
    }
}

function ConvertTo-ReportSummaryData {
    [CmdletBinding()]
    param($Summary, [Parameter(Mandatory)][string[]]$PropertyNames)
    if ($null -eq $Summary) { return $null }
    $plain = [ordered]@{}
    foreach ($name in $PropertyNames) {
        $value = Get-ReportPropertyValue $Summary $name $null
        $plain[$name] = if ($null -eq $value) { $null } elseif ($value -is [bool]) { [bool]$value } elseif ($value -is [ValueType]) { $value } else { [string]$value }
    }
    return $plain
}

function Get-ReportCaptureHash {
    [CmdletBinding()]
    param([string[]]$StdOut = @(), [string[]]$StdErr = @())
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append("STDOUT`n")
    foreach ($line in $StdOut) { [void]$builder.Append($line); [void]$builder.Append("`n") }
    [void]$builder.Append("STDERR`n")
    foreach ($line in $StdErr) { [void]$builder.Append($line); [void]$builder.Append("`n") }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString()))
        return ([BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function New-WorkflowJsonReportObject {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $commands = @()
    $nativeOutputCaptures = @()
    $captureIdsByHash = @{}
    foreach ($command in @($State.Commands)) {
        $exitCode = Get-ReportPropertyValue $command 'ExitCode' $null
        $stdOut = @(ConvertTo-ReportStringArray (Get-ReportPropertyValue $command 'Output' @()))
        $stdErr = @(ConvertTo-ReportStringArray (Get-ReportPropertyValue $command 'ErrorOutput' @()))
        $captureHash = Get-ReportCaptureHash -StdOut $stdOut -StdErr $stdErr
        if (-not $captureIdsByHash.ContainsKey($captureHash)) {
            $captureId = 'capture-' + ($captureIdsByHash.Count + 1)
            $captureIdsByHash[$captureHash] = $captureId
            $nativeOutputCaptures += [ordered]@{ CaptureId=$captureId; StdOut=$stdOut; StdErr=$stdErr }
        }
        else { $captureId = $captureIdsByHash[$captureHash] }
        $commands += [ordered]@{
            Kind = [string](Get-ReportPropertyValue $command 'Kind' '')
            Input = [string](Get-ReportPropertyValue $command 'Input' '')
            Program = [string](Get-ReportPropertyValue $command 'Program' '')
            Arguments = @(ConvertTo-ReportStringArray (Get-ReportPropertyValue $command 'Arguments' @()))
            WorkingDirectory = [string](Get-ReportPropertyValue $command 'WorkingDirectory' '')
            ExitCode = if ($null -eq $exitCode) { $null } else { [int]$exitCode }
            Status = [string](Get-ReportPropertyValue $command 'Status' '')
            CaptureId = $captureId
            StdOutLineCount = $stdOut.Count
            StdErrLineCount = $stdErr.Count
        }
    }
    $demCandidates = @()
    foreach ($candidate in @($State.DemCandidates)) {
        $candidateData = ConvertTo-ReportFileData $candidate
        $candidateData['IsZeroByte'] = [bool](Get-ReportPropertyValue $candidate 'IsZeroByte' $false)
        $demCandidates += $candidateData
    }
    $configurationRules = @()
    foreach ($item in @($State.ConfigurationRuleDiagnostics)) {
        $configurationRules += [ordered]@{ Index=[int](Get-ReportPropertyValue $item 'Index' 0); Name=[string](Get-ReportPropertyValue $item 'Name' ''); Group=[string](Get-ReportPropertyValue $item 'Group' ''); ExpectedCount=[int](Get-ReportPropertyValue $item 'ExpectedCount' 0); SearchLocation=[string](Get-ReportPropertyValue $item 'SearchLocation' ''); Pattern=[string](Get-ReportPropertyValue $item 'Pattern' ''); RuntimeType=[string](Get-ReportPropertyValue $item 'RuntimeType' '') }
    }
    $expectedFiles = @()
    foreach ($item in @($State.ExpectedFiles)) {
        $expectedFiles += [ordered]@{
            Rule = [string](Get-ReportPropertyValue $item 'Rule' '')
            Role = [string](Get-ReportPropertyValue $item 'Role' '')
            Pattern = [string](Get-ReportPropertyValue $item 'Pattern' '')
            ExpectedCount = [int](Get-ReportPropertyValue $item 'ExpectedCount' 0)
            SearchLocation = [string](Get-ReportPropertyValue $item 'SearchLocation' '')
            Group = [string](Get-ReportPropertyValue $item 'Group' '')
        }
    }
    $locatedFiles = @()
    foreach ($item in @($State.LocatedFiles)) { $locatedFiles += ConvertTo-ReportFileData $item }
    $copyMappings = @()
    foreach ($item in @($State.FilesProposedForCopy)) {
        $copyMappings += [ordered]@{
            Source = [string](Get-ReportPropertyValue $item 'Source' '')
            Destination = [string](Get-ReportPropertyValue $item 'StagingPath' '')
            ProductRule = [string](Get-ReportPropertyValue $item 'ProductRule' '')
            Group = [string](Get-ReportPropertyValue $item 'Group' '')
            Action = [string](Get-ReportPropertyValue $item 'Action' '')
            DestinationAlreadyExists = [bool](Get-ReportPropertyValue $item 'DestinationAlreadyExists' $false)
            DestinationItemType = [string](Get-ReportPropertyValue $item 'DestinationItemType' '')
            DuplicateTarget = [bool](Get-ReportPropertyValue $item 'DuplicateTarget' $false)
            DuplicateSources = @(ConvertTo-ReportStringArray (Get-ReportPropertyValue $item 'DuplicateSources' @()))
            ConflictReason = Get-ReportPropertyValue $item 'ConflictReason' $null
        }
    }
    $copyConflicts = @()
    foreach ($item in @($State.CopyPlanConflictDetails)) {
        $copyConflicts += [ordered]@{ SourcePath=Get-ReportPropertyValue $item 'SourcePath' $null; DestinationPath=[string](Get-ReportPropertyValue $item 'DestinationPath' ''); ProductRule=Get-ReportPropertyValue $item 'ProductRule' $null; Group=Get-ReportPropertyValue $item 'Group' $null; ConflictType=[string](Get-ReportPropertyValue $item 'ConflictType' ''); DestinationAlreadyExists=[bool](Get-ReportPropertyValue $item 'DestinationAlreadyExists' $false); DestinationItemType=[string](Get-ReportPropertyValue $item 'DestinationItemType' ''); DuplicateTarget=[bool](Get-ReportPropertyValue $item 'DuplicateTarget' $false); DuplicateSources=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $item 'DuplicateSources' @())) }
    }
    $duplicateDestinations = @()
    foreach ($item in @($State.DuplicateDestinationDetails)) {
        $duplicateDestinations += [ordered]@{ DestinationPath=[string](Get-ReportPropertyValue $item 'DestinationPath' ''); SourcePaths=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $item 'SourcePaths' @())); ConflictType=[string](Get-ReportPropertyValue $item 'ConflictType' '') }
    }
    $existingStagingItems = @()
    foreach ($item in @($State.ExistingStagingItems)) {
        $existingStagingItems += [ordered]@{ Path=[string](Get-ReportPropertyValue $item 'Path' ''); ItemType=[string](Get-ReportPropertyValue $item 'ItemType' '') }
    }
    $fatalDetails = @()
    foreach ($detail in @($State.FatalErrorDetails)) {
        if ($detail -is [System.Management.Automation.ErrorRecord]) {
            $detail = New-WorkflowFailureDetail -ErrorRecord $detail
        }
        elseif ($detail -is [Exception]) {
            $detail = [pscustomobject]@{ Message=$detail.Message; ExceptionType=$detail.GetType().FullName }
        }
        $fatalDetails += [ordered]@{
            Message = [string](Get-ReportPropertyValue $detail 'Message' '')
            ExceptionType = [string](Get-ReportPropertyValue $detail 'ExceptionType' '')
            ScriptName = [string](Get-ReportPropertyValue $detail 'ScriptName' '')
            ScriptLineNumber = Get-ReportPropertyValue $detail 'ScriptLineNumber' $null
            OffsetInLine = Get-ReportPropertyValue $detail 'OffsetInLine' $null
            PositionMessage = [string](Get-ReportPropertyValue $detail 'PositionMessage' '')
            FunctionName = [string](Get-ReportPropertyValue $detail 'FunctionName' '')
            InvocationMyCommand = [string](Get-ReportPropertyValue $detail 'InvocationMyCommand' '')
            InvocationScriptLineNumber = Get-ReportPropertyValue $detail 'InvocationScriptLineNumber' $null
            InvocationOffsetInLine = Get-ReportPropertyValue $detail 'InvocationOffsetInLine' $null
            ScriptStackTrace = [string](Get-ReportPropertyValue $detail 'ScriptStackTrace' '')
        }
    }
    $mainProperties = @('ExpectedFileCount','ActualFileCount','ExpectedDirectoryCount','ActualDirectoryCount','ExpectedRawCount','ActualRawCount','ExpectedShellScriptCount','ActualShellScriptCount','ExpectedReportCount','ActualReportCount','ExpectedPngCount','ActualPngCount','ExpectedGnuCount','ActualGnuCount','ExpectedLisCount','ActualLisCount')
    $colorProperties = @('ExpectedFileCount','ActualFileCount','ExpectedRawCount','ActualRawCount','ExpectedShellScriptCount','ActualShellScriptCount')
    $outputStructure = $State.OutputStructure
    $stagingValidation = $State.StagingValidation
    return [ordered]@{
        SchemaVersion = '1.0'
        Workflow = [ordered]@{ ProjectName=[string]$State.ProjectName; ScriptVersion=[string]$State.ScriptVersion; StartTime=[string]$State.StartTime; EndTime=[string]$State.EndTime; Success=[bool]$State.FinalSuccess; DryRun=[bool]$State.DryRun; IncludeColor=[bool]$State.IncludeColor; HostOperatingSystem=[string]$State.HostOperatingSystem; PowerShellVersion=[string]$State.PowerShellVersion; PowerShellEdition=[string]$State.PowerShellEdition }
        Paths = [ordered]@{ SourceProjectDirectory=[string]$State.SourceProjectDirectory; SourceImagesProjectDirectory=[string]$State.SourceImagesProjectDirectory; OutputProductsDirectory=[string]$State.OutputProductsDirectory; StagingDirectory=[string]$State.StagingDirectory; ConfigurationPath=[string]$State.ConfigurationPath; LogPath=[string]$State.LogPath; TextReportPath=[string]$State.TextReportPath; JsonReportPath=[string]$State.JsonReportPath }
        ConfigurationRules = $configurationRules
        DEM = [ordered]@{ Selected=[string]$State.DemSelected; SelectedPath=[string]$State.DemSelectedPath; SelectionMethod=[string]$State.DemSelectionMethod; Candidates=$demCandidates; Warnings=@(ConvertTo-ReportStringArray $State.DemSelectionWarnings) }
        SupInputs = @(ConvertTo-ReportStringArray $State.SupInputs)
        Commands = $commands
        NativeOutputCaptures = $nativeOutputCaptures
        Products = [ordered]@{ Expected=$expectedFiles; Located=$locatedFiles; Missing=@(ConvertTo-ReportStringArray $State.MissingFiles); ZeroByte=@(ConvertTo-ReportStringArray $State.ZeroByteFiles); Ambiguous=@(ConvertTo-ReportStringArray $State.DuplicateOrAmbiguousMatches); StructureErrors=@(ConvertTo-ReportStringArray $State.StructureErrors); OutputStructure=[ordered]@{ RequireColorDirectory=[bool](Get-ReportPropertyValue $outputStructure 'RequireColorDirectory' $false); MainFolder=$(ConvertTo-ReportSummaryData (Get-ReportPropertyValue $outputStructure 'MainFolder' $null) $mainProperties); ColorFolder=$(ConvertTo-ReportSummaryData (Get-ReportPropertyValue $outputStructure 'ColorFolder' $null) $colorProperties) } }
        CopyPlan = [ordered]@{ CanExecute=$State.CopyPlanCanExecute; ConflictCount=[int]$State.CopyPlanConflictCount; BlockReasons=@(ConvertTo-ReportStringArray $State.CopyPlanBlockReasons); Mappings=$copyMappings; ConflictDetails=$copyConflicts; DuplicateDestinations=$duplicateDestinations; ExistingStagingItems=$existingStagingItems; FilesActuallyCopied=@(ConvertTo-ReportStringArray $State.FilesActuallyCopied); FilesSkipped=@(ConvertTo-ReportStringArray $State.FilesSkipped); ExistingConflicts=@(ConvertTo-ReportStringArray $State.ExistingStagingConflicts); UnexpectedItems=@(ConvertTo-ReportStringArray $State.UnexpectedStagingItems); StagingDirectoryExists=$State.StagingDirectoryExists; StagingDirectoryStatus=[string]$State.StagingDirectoryStatus }
        StagingValidation = $(if ($null -eq $stagingValidation) { $null } else { [ordered]@{ IsValid=$(Get-ReportPropertyValue $stagingValidation 'IsValid' $null); Status=[string](Get-ReportPropertyValue $stagingValidation 'Status' ''); Missing=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $stagingValidation 'Missing' @())); ZeroByte=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $stagingValidation 'ZeroByte' @())); Unexpected=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $stagingValidation 'Unexpected' @())); FilenameMismatches=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $stagingValidation 'FilenameMismatches' @())); StructureErrors=@(ConvertTo-ReportStringArray (Get-ReportPropertyValue $stagingValidation 'StructureErrors' @())); MainFolder=$(ConvertTo-ReportSummaryData (Get-ReportPropertyValue $stagingValidation 'MainFolder' $null) $mainProperties); ColorFolder=$(ConvertTo-ReportSummaryData (Get-ReportPropertyValue $stagingValidation 'ColorFolder' $null) $colorProperties) } })
        Diagnostics = [ordered]@{ Warnings=@(ConvertTo-ReportStringArray $State.Warnings); FatalErrors=@(ConvertTo-ReportStringArray $State.FatalErrors); FatalErrorDetails=$fatalDetails }
    }
}

function Save-WorkflowReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [scriptblock]$JsonSerializer)
    $State.EndTime = (Get-Date).ToString('o')
    $supInputs = @($State.SupInputs)
    $demCandidates = @($State.DemCandidates)
    $demSelectionWarnings = @($State.DemSelectionWarnings)
    $warnings = @($State.Warnings)
    $fatalErrors = @($State.FatalErrors)
    $fatalErrorDetails = @($State.FatalErrorDetails)
    $missingFiles = @($State.MissingFiles)
    $zeroByteFiles = @($State.ZeroByteFiles)
    $ambiguousMatches = @($State.DuplicateOrAmbiguousMatches)
    $unexpectedStagingItems = @($State.UnexpectedStagingItems)
    $structureErrors = @($State.StructureErrors)
    $configurationRuleDiagnostics = @($State.ConfigurationRuleDiagnostics)
    $filesProposedForCopy = @($State.FilesProposedForCopy)
    $existingStagingConflicts = @($State.ExistingStagingConflicts)
    $copyPlanConflictDetails = @($State.CopyPlanConflictDetails)
    $copyPlanBlockReasons = @($State.CopyPlanBlockReasons)
    $duplicateDestinationDetails = @($State.DuplicateDestinationDetails)
    $existingStagingItems = @($State.ExistingStagingItems)
    $demCandidateText = (($demCandidates | ForEach-Object { '{0} [{1}] {2} bytes {3}' -f $_.Name, $_.LastWriteTime, $_.Length, $_.FullName }) -join ' | ')
    $configurationRuleText = (@($configurationRuleDiagnostics | ForEach-Object { "[$($_.Index)] Name='$($_.Name)' Group='$($_.Group)' Count=$($_.ExpectedCount) Location='$($_.SearchLocation)' Type='$($_.RuntimeType)'" }) -join ' | ')
    $text = @(
        "SOCET Ortho Workflow Report", "Run: $($State.StartTime) to $($State.EndTime)", "Success: $($State.FinalSuccess)",
        "Project: $($State.ProjectName)", "Source data project: $($State.SourceProjectDirectory)", "Source images project: $($State.SourceImagesProjectDirectory)", "Output products: $($State.OutputProductsDirectory)",
        "Desktop staging: $($State.StagingDirectory)", "Dry run: $($State.DryRun)", "COLOR: $($State.IncludeColor)",
        "SUP inputs ($($supInputs.Count)): $($supInputs -join ', ')", "DEM: $($State.DemSelected)", "DEM path: $($State.DemSelectedPath)", "DEM selection method: $($State.DemSelectionMethod)",
        "DEM candidates ($($demCandidates.Count)): $demCandidateText",
        "DEM selection warnings ($($demSelectionWarnings.Count)): $($demSelectionWarnings -join ' | ')",
        "Warnings ($($warnings.Count)): $($warnings -join ' | ')", "Fatal errors ($($fatalErrors.Count)): $($fatalErrors -join ' | ')",
        "Validated product rules ($($configurationRuleDiagnostics.Count)): $configurationRuleText",
        "CopyPlanCanExecute: $($State.CopyPlanCanExecute)", "CopyPlanConflictCount: $($State.CopyPlanConflictCount)", "CopyPlanBlockReasons ($($copyPlanBlockReasons.Count)): $($copyPlanBlockReasons -join ' | ')", "Staging directory exists: $($State.StagingDirectoryExists)", "Staging directory status: $($State.StagingDirectoryStatus)",
        "Existing staging conflicts ($($existingStagingConflicts.Count)): $($existingStagingConflicts -join ' | ')",
        "Missing ($($missingFiles.Count)): $($missingFiles -join ' | ')", "Zero-byte ($($zeroByteFiles.Count)): $($zeroByteFiles -join ' | ')",
        "Ambiguous ($($ambiguousMatches.Count)): $($ambiguousMatches -join ' | ')",
        "Unexpected staging items ($($unexpectedStagingItems.Count)): $($unexpectedStagingItems -join ' | ')",
        "Structure errors ($($structureErrors.Count)): $($structureErrors -join ' | ')",
        'Commands:'
    )
    $text += 'Planned copy mappings:'
    foreach ($item in $filesProposedForCopy) {
        $text += "source='$($item.Source)' destination='$($item.StagingPath)' rule='$($item.ProductRule)' group='$($item.Group)' destinationExists=$($item.DestinationAlreadyExists) destinationType='$($item.DestinationItemType)' duplicateTarget=$($item.DuplicateTarget) conflict='$($item.ConflictReason)'"
    }
    $text += 'Copy-plan conflict details:'
    foreach ($conflict in $copyPlanConflictDetails) {
        $text += "type='$($conflict.ConflictType)' source='$($conflict.SourcePath)' destination='$($conflict.DestinationPath)' destinationExists=$($conflict.DestinationAlreadyExists) destinationType='$($conflict.DestinationItemType)' duplicateSources='$($conflict.DuplicateSources -join ', ')'"
    }
    $text += 'Duplicate destination details:'
    foreach ($duplicate in $duplicateDestinationDetails) {
        $text += "destination='$($duplicate.DestinationPath)' sources='$($duplicate.SourcePaths -join ', ')'"
    }
    $text += 'Existing staging items:'
    foreach ($existingItem in $existingStagingItems) { $text += "path='$($existingItem.Path)' type='$($existingItem.ItemType)'" }
    if ($fatalErrorDetails.Count -gt 0) {
        $text += 'Fatal diagnostics:'
        foreach ($detail in $fatalErrorDetails) {
            if ($detail -is [System.Management.Automation.ErrorRecord]) { $detail = New-WorkflowFailureDetail -ErrorRecord $detail }
            elseif ($detail -is [Exception]) { $detail = [pscustomobject]@{ Message=$detail.Message; ExceptionType=$detail.GetType().FullName } }
            $text += "Exception message: $($detail.Message)"
            $text += "Exception type: $(Get-ReportPropertyValue $detail 'ExceptionType' '')"
            $text += "Script name: $(Get-ReportPropertyValue $detail 'ScriptName' '')"
            $text += "Line: $(Get-ReportPropertyValue $detail 'ScriptLineNumber' ''); offset: $(Get-ReportPropertyValue $detail 'OffsetInLine' ''); function: $(Get-ReportPropertyValue $detail 'FunctionName' '')"
            $text += "Position: $(Get-ReportPropertyValue $detail 'PositionMessage' '')"
            $text += "Invocation command: $(Get-ReportPropertyValue $detail 'InvocationMyCommand' ''); invocation line: $(Get-ReportPropertyValue $detail 'InvocationScriptLineNumber' ''); invocation offset: $(Get-ReportPropertyValue $detail 'InvocationOffsetInLine' '')"
            $text += "Stack trace: $(Get-ReportPropertyValue $detail 'ScriptStackTrace' '')"
        }
    }
    if ($State.OutputStructure) {
        $main = $State.OutputStructure.MainFolder; $color = $State.OutputStructure.ColorFolder
        $text += "Main folder: files $($main.ActualFileCount)/$($main.ExpectedFileCount), COLOR directories $($main.ActualDirectoryCount)/$($main.ExpectedDirectoryCount), RAW $($main.ActualRawCount)/$($main.ExpectedRawCount), SH $($main.ActualShellScriptCount)/$($main.ExpectedShellScriptCount), REP $($main.ActualReportCount)/$($main.ExpectedReportCount), PNG $($main.ActualPngCount)/$($main.ExpectedPngCount), GNU $($main.ActualGnuCount)/$($main.ExpectedGnuCount), LIS $($main.ActualLisCount)/$($main.ExpectedLisCount)"
        $text += "COLOR folder: files $($color.ActualFileCount)/$($color.ExpectedFileCount), RAW $($color.ActualRawCount)/$($color.ExpectedRawCount), SH $($color.ActualShellScriptCount)/$($color.ExpectedShellScriptCount)"
    }
    if ($State.StagingValidation) {
        $stagingMissing = @($State.StagingValidation.Missing)
        $stagingZeroByte = @($State.StagingValidation.ZeroByte)
        $stagingUnexpected = @($State.StagingValidation.Unexpected)
        $stagingFilenameMismatches = @($State.StagingValidation.FilenameMismatches)
        $text += "Staging validation: $($State.StagingValidation.Status); valid=$($State.StagingValidation.IsValid)"
        $text += "Staging missing ($($stagingMissing.Count)): $($stagingMissing -join ' | ')"
        $text += "Staging zero-byte ($($stagingZeroByte.Count)): $($stagingZeroByte -join ' | ')"
        $text += "Staging unexpected ($($stagingUnexpected.Count)): $($stagingUnexpected -join ' | ')"
        $text += "Staging filename mismatches ($($stagingFilenameMismatches.Count)): $($stagingFilenameMismatches -join ' | ')"
    }
    foreach ($command in $State.Commands) { $text += "[$($command.Status)] exit=$($command.ExitCode) cwd=$($command.WorkingDirectory) :: $(ConvertTo-DisplayCommand $command.Program $command.Arguments)" }
    [IO.File]::WriteAllLines($State.TextReportPath, [string[]]$text, [Text.Encoding]::UTF8)
    Write-OrthoLog -State $State -Level INFO -Message 'Writing machine-readable JSON report.'
    $jsonObject = New-WorkflowJsonReportObject -State $State
    $temporaryJsonPath = $State.JsonReportPath + '.tmp-' + [guid]::NewGuid().ToString('N')
    try {
        $json = if ($JsonSerializer) { & $JsonSerializer $jsonObject } else { $jsonObject | ConvertTo-Json -Depth 6 }
        if ([string]::IsNullOrWhiteSpace([string]$json)) { throw 'JSON serializer returned no content.' }
        [IO.File]::WriteAllText($temporaryJsonPath, [string]$json, [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryJsonPath -Destination $State.JsonReportPath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryJsonPath) { Remove-Item -LiteralPath $temporaryJsonPath -Force -ErrorAction SilentlyContinue }
    }
    Write-OrthoLog -State $State -Level INFO -Message "Machine-readable JSON report written: $($State.JsonReportPath)"
    return [pscustomobject]@{ TextReportPath=$State.TextReportPath; JsonReportPath=$State.JsonReportPath; JsonWritten=$true }
}

function Complete-WorkflowReporting {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [int]$ExitCode = 0, [scriptblock]$JsonSerializer)
    try {
        Save-WorkflowReport -State $State -JsonSerializer $JsonSerializer | Out-Null
        return $ExitCode
    }
    catch {
        $message = "Machine-readable JSON report failed: $($_.Exception.Message)"
        $State.FinalSuccess = $false
        try { Write-OrthoLog -State $State -Level ERROR -Message $message }
        catch { Write-Host "ERROR: $message" }
        try { Add-Content -LiteralPath $State.TextReportPath -Value $message -Encoding UTF8 }
        catch { Write-Host "ERROR: Unable to append JSON failure to text report: $($_.Exception.Message)" }
        return 1
    }
}

Export-ModuleMember -Function @(
    'Test-IsWindowsHost','Assert-SafeProjectName','Assert-SafeLeafName','Assert-ExistingDirectory','Resolve-ContainedPath','Resolve-ConfiguredWorkingDirectory','Get-WorkflowReportContext','New-WorkflowState','Write-OrthoLog','New-WorkflowFailureDetail',
    'Import-OrthoWorkflowConfiguration','Get-UnresolvedConfigurationItems','Get-OrthoSupFiles','Test-InteractiveSelectionAvailable','Select-OrthoDemFile','Resolve-OrthoDemFile','New-OrthoCommandSpecs','ConvertTo-DisplayCommand','ConvertTo-SocetCmdCall',
    'New-OrthoBatchFile','ConvertTo-StartProcessArgumentString','Invoke-OrthoExternalCommand','Write-OrthoExternalResultLog','Update-OrthoBatchResults','Get-ProductValidation','New-ProductCopyPlan','Invoke-CommandSpec','Invoke-ProductCopyPlan','Test-StagedProductSet','New-WorkflowJsonReportObject','Save-WorkflowReport','Complete-WorkflowReporting'
)
