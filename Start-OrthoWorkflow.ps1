#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OrthoLauncherScriptRoot = $PSScriptRoot
Import-Module (Join-Path $script:OrthoLauncherScriptRoot 'Modules/OrthoWorkflow.psm1') -Force

function Resolve-OrthoLauncherWorkflowPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ScriptRoot)

    $workflowScript = [IO.Path]::GetFullPath((Join-Path $ScriptRoot 'Run-OrthoWorkflow.ps1'))
    if (-not (Test-Path -LiteralPath $workflowScript -PathType Leaf)) {
        throw "Required workflow script was not found beside the launcher: $workflowScript"
    }
    return $workflowScript
}

function Read-OrthoLauncherRequiredValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][scriptblock]$ReadInput,
        [string]$EmptyMessage = 'A value is required.',
        [switch]$Trim
    )

    while ($true) {
        $value = [string](& $ReadInput $Prompt)
        if ($Trim) { $value = $value.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
        Write-Host $EmptyMessage -ForegroundColor Yellow
    }
}

function Read-OrthoLauncherYesNo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][scriptblock]$ReadInput
    )

    while ($true) {
        $answer = ([string](& $ReadInput $Prompt)).Trim()
        if ($answer -match '^(?i:y|yes)$') { return $true }
        if ($answer -match '^(?i:n|no)$') { return $false }
        Write-Host 'Please enter Y, Yes, N, or No.' -ForegroundColor Yellow
    }
}

function Read-OrthoLauncherMode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$ReadInput)

    while ($true) {
        Write-Host ''
        Write-Host 'Select workflow mode:'
        Write-Host ''
        Write-Host '[1] Dry run only'
        Write-Host '    Show planned commands and validation without executing SOCET or copying products.'
        Write-Host ''
        Write-Host '[2] Full workflow'
        Write-Host '    Run ortho conversions, run the DEM conversion, validate products, and stage them on the Desktop.'
        Write-Host ''
        Write-Host '[3] Use existing products'
        Write-Host '    Skip SOCET conversions, validate existing products, and stage them on the Desktop.'
        Write-Host ''
        Write-Host '[C] Cancel'
        $selection = ([string](& $ReadInput 'Selection')).Trim()
        switch -Regex ($selection) {
            '^1$' { return 'DryRun' }
            '^2$' { return 'FullWorkflow' }
            '^3$' { return 'ExistingProducts' }
            '^(?i:c|cancel)$' { return 'Cancel' }
            default { Write-Host 'Please enter 1, 2, 3, C, or Cancel.' -ForegroundColor Yellow }
        }
    }
}

function Read-OrthoLauncherSupSelectionMode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$ReadInput)

    while ($true) {
        Write-Host ''
        Write-Host 'How would you like to select your ortho files?'
        Write-Host '[1] Automatic (recommended)'
        Write-Host '    Discover and use the project''s relevant *_o.sup files.'
        Write-Host '[2] Manual'
        Write-Host '    Review discovered files and choose the approved *_o.sup files.'
        $selection = ([string](& $ReadInput 'Ortho selection (press Enter for Automatic)')).Trim()
        switch -Regex ($selection) {
            '^$|^1$|^(?i:automatic)$' { return 'Automatic' }
            '^2$|^(?i:manual)$' { return 'Manual' }
            '^(?i:c|cancel)$' { return 'Cancel' }
            default { Write-Host 'Please enter 1, 2, Automatic, Manual, or C to cancel.' -ForegroundColor Yellow }
        }
    }
}

function Assert-OrthoLauncherSupFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedProjectDirectory
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($fullPath) -ine '.sup' -or $fullPath -notmatch '_o\.sup$') { throw "Selected ortho file must be a *_o.sup file: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Selected ortho SUP file was not found: $fullPath" }
    $file = Get-Item -LiteralPath $fullPath -Force
    if ($file.PSIsContainer) { throw "Selected ortho SUP path must be a file: $fullPath" }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectDirectory) -and (Test-Path -LiteralPath $ExpectedProjectDirectory -PathType Container)) {
        $expectedDirectory = [IO.Path]::GetFullPath($ExpectedProjectDirectory).TrimEnd([char]'/', [char]'\')
        $selectedDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $file.FullName)).TrimEnd([char]'/', [char]'\')
        if (-not $selectedDirectory.Equals($expectedDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Selected ortho SUP must be a top-level file in the selected SOCET data project directory: $expectedDirectory"
        }
    }
    return $file.FullName
}

function Select-OrthoLauncherSupFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ExpectedProjectDirectory)

    if (-not (Test-Path -LiteralPath $ExpectedProjectDirectory -PathType Container)) {
        throw "The selected SOCET data project directory is unavailable for manual SUP selection: $ExpectedProjectDirectory"
    }
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
        throw 'The native ortho-file picker requires an STA Windows PowerShell session. Start Windows PowerShell with -STA and run the launcher again.'
    }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $list = New-Object System.Windows.Forms.CheckedListBox
    $addButton = New-Object System.Windows.Forms.Button
    $okButton = New-Object System.Windows.Forms.Button
    $cancelButton = New-Object System.Windows.Forms.Button
    try {
        $form.Text = 'Select approved SOCET ortho SUP files'
        $form.StartPosition = 'CenterScreen'
        $form.Size = New-Object System.Drawing.Size(900, 500)
        $form.MinimizeBox = $false
        $form.MaximizeBox = $false
        $label = New-Object System.Windows.Forms.Label
        $label.Text = 'Checked files will be converted and determine the products required for Desktop staging.'
        $label.AutoSize = $true; $label.Location = New-Object System.Drawing.Point(12, 12)
        $list.Location = New-Object System.Drawing.Point(12, 40); $list.Size = New-Object System.Drawing.Size(860, 340)
        $list.CheckOnClick = $true; $list.HorizontalScrollbar = $true
        foreach ($file in @(Get-ChildItem -LiteralPath $ExpectedProjectDirectory -File -Filter '*_o.sup' | Sort-Object Name)) { [void]$list.Items.Add($file.FullName, $true) }
        $addButton.Text = 'Add SUP files...'; $addButton.Location = New-Object System.Drawing.Point(12, 400); $addButton.Size = New-Object System.Drawing.Size(130, 28)
        $okButton.Text = 'Use selected files'; $okButton.Location = New-Object System.Drawing.Point(620, 400); $okButton.Size = New-Object System.Drawing.Size(120, 28)
        $cancelButton.Text = 'Cancel'; $cancelButton.Location = New-Object System.Drawing.Point(752, 400); $cancelButton.Size = New-Object System.Drawing.Size(120, 28)
        $addButton.Add_Click({
            $dialog = New-Object System.Windows.Forms.OpenFileDialog
            try {
                $dialog.Title = 'Add SOCET ortho SUP files'; $dialog.Filter = 'SOCET ortho SUP files (*_o.sup)|*_o.sup|All SUP files (*.sup)|*.sup|All files (*.*)|*.*'; $dialog.Multiselect = $true; $dialog.CheckFileExists = $true; $dialog.InitialDirectory = $ExpectedProjectDirectory
                if ($dialog.ShowDialog().ToString() -eq 'OK') {
                    try {
                        foreach ($path in @($dialog.FileNames)) {
                            $validated = Assert-OrthoLauncherSupFile -Path $path -ExpectedProjectDirectory $ExpectedProjectDirectory
                            if (@($list.Items | ForEach-Object { [string]$_ }) -notcontains $validated) { [void]$list.Items.Add($validated, $true) }
                        }
                    }
                    catch {
                        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Invalid SUP selection', 'OK', 'Warning') | Out-Null
                    }
                }
            }
            finally { $dialog.Dispose() }
        })
        $okButton.Add_Click({
            if ($list.CheckedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('Select at least one *_o.sup file, or Cancel.', 'No SUP files selected', 'OK', 'Warning') | Out-Null; return }
            $form.Tag = @($list.CheckedItems | ForEach-Object { [string]$_ }); $form.DialogResult = [System.Windows.Forms.DialogResult]::OK; $form.Close()
        })
        $cancelButton.Add_Click({ $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $form.Close() })
        [void]$form.Controls.AddRange(@($label,$list,$addButton,$okButton,$cancelButton))
        if ($form.ShowDialog().ToString() -ne 'OK') { return $null }
        return @($form.Tag)
    }
    finally { $form.Dispose() }
}

function Get-OrthoLauncherModeDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DryRun','FullWorkflow','ExistingProducts')][string]$Mode)

    switch ($Mode) {
        'DryRun' { return [pscustomobject]@{ Label='Dry run'; Parameters=@{ DryRun=$true } } }
        'FullWorkflow' { return [pscustomobject]@{ Label='Full workflow'; Parameters=@{ ConfirmRealExecution=$true } } }
        'ExistingProducts' { return [pscustomobject]@{ Label='Existing products only'; Parameters=@{ SkipConversions=$true; ConfirmRealExecution=$true } } }
    }
}

function Assert-OrthoLauncherStatisticsLisFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($fullPath) -ine '.lis') { throw "Selected statistics file must use the .lis extension: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Selected statistics LIS file was not found: $fullPath" }
    $file = Get-Item -LiteralPath $fullPath -Force
    if ($file.PSIsContainer -or $file.Length -le 0) { throw "Selected statistics LIS file must be a nonzero file: $fullPath" }
    return $file.FullName
}

function Select-OrthoLauncherFile {
    [CmdletBinding()]
    param(
        [string]$InitialDirectory,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][scriptblock]$ValidateSelection
    )

    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA) {
        throw 'The native file picker requires an STA Windows PowerShell session. Start Windows PowerShell with -STA and run the launcher again.'
    }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    try {
        $dialog.Title = $Title
        $dialog.Filter = $Filter
        $dialog.FilterIndex = 1
        $dialog.Multiselect = $false
        $dialog.CheckFileExists = $true
        if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory -PathType Container)) {
            $dialog.InitialDirectory = $InitialDirectory
        }
        if ($dialog.ShowDialog().ToString() -ne 'OK') { return $null }
        return & $ValidateSelection $dialog.FileName
    }
    finally {
        $dialog.Dispose()
    }
}

function Select-OrthoLauncherStatisticsLisFile {
    [CmdletBinding()]
    param([string]$ExpectedImagesProjectDirectory)
    return Select-OrthoLauncherFile -InitialDirectory $ExpectedImagesProjectDirectory -Title 'Select required statistics .lis file' -Filter 'Statistics LIS files (*.lis)|*.lis|All files (*.*)|*.*' -ValidateSelection { param($Path) Assert-OrthoLauncherStatisticsLisFile -Path $Path }
}

function Assert-OrthoLauncherReadmeFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "README file was not found: $fullPath" }
    $file = Get-Item -LiteralPath $fullPath -Force
    if ($file.PSIsContainer) { throw "README path must be a file: $fullPath" }
    [IO.File]::ReadAllBytes($file.FullName) | Out-Null
    return $file.FullName
}

function Select-OrthoLauncherReadmeFile {
    [CmdletBinding()]
    param([string]$ExpectedProjectDirectory)
    return Select-OrthoLauncherFile -InitialDirectory $ExpectedProjectDirectory -Title 'Select required project README file' -Filter 'Common README files (*.txt;*.md;*.rtf;*.log)|*.txt;*.md;*.rtf;*.log|All files (*.*)|*.*' -ValidateSelection { param($Path) Assert-OrthoLauncherReadmeFile -Path $Path }
}

function Assert-OrthoLauncherDemFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ExpectedProjectDirectory
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($fullPath) -ine '.dth') { throw "Selected DEM file must use the .dth extension: $fullPath" }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Selected DEM file was not found: $fullPath" }
    $file = Get-Item -LiteralPath $fullPath -Force
    if ($file.PSIsContainer -or $file.Length -le 0) { throw "Selected DEM file must be a nonzero file: $fullPath" }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedProjectDirectory) -and (Test-Path -LiteralPath $ExpectedProjectDirectory -PathType Container)) {
        $expectedDirectory = [IO.Path]::GetFullPath($ExpectedProjectDirectory).TrimEnd([char]'/', [char]'\')
        $selectedDirectory = [IO.Path]::GetFullPath((Split-Path -Parent $file.FullName)).TrimEnd([char]'/', [char]'\')
        if (-not $selectedDirectory.Equals($expectedDirectory, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Selected DEM must be a top-level file in the selected SOCET data project directory: $expectedDirectory"
        }
    }
    return $file.FullName
}

function Select-OrthoLauncherDemFile {
    [CmdletBinding()]
    param([string]$ExpectedProjectDirectory)
    return Select-OrthoLauncherFile -InitialDirectory $ExpectedProjectDirectory -Title 'Select required DEM .dth file' -Filter 'SOCET DEM files (*.dth)|*.dth|All files (*.*)|*.*' -ValidateSelection { param($Path) Assert-OrthoLauncherDemFile -Path $Path -ExpectedProjectDirectory $ExpectedProjectDirectory }
}

function Read-OrthoLauncherProducer {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$ReadInput)

    $producers = [ordered]@{
        '1' = 'Lenny Druelle'
        '2' = 'Patricio Santos'
        '3' = 'Chloe Billet'
        '4' = 'Luke Meier'
        '5' = 'Alexander Burchuladze'
    }
    Write-Host ''
    Write-Host 'Select producer:'
    foreach ($choice in $producers.Keys) { Write-Host "$choice) $($producers[$choice])" }
    while ($true) {
        $producerChoice = ([string](& $ReadInput 'Who is the producer?')).Trim()
        if (-not $producers.Contains($producerChoice)) {
            Write-Host 'Please choose 1-5.' -ForegroundColor Yellow
            continue
        }
        $producerName = $producers[$producerChoice]
        if (Read-OrthoLauncherYesNo -Prompt "Confirm producer name: $producerName [Y/N]" -ReadInput $ReadInput) { return $producerName }
    }
}

function Invoke-OrthoWorkflowLauncher {
    [CmdletBinding()]
    param(
        [string]$ScriptRoot = $script:OrthoLauncherScriptRoot,
        [scriptblock]$ReadInput = { param($Prompt) Read-Host -Prompt $Prompt },
        [scriptblock]$StatisticsFileSelector,
        [scriptblock]$ProducerSelector,
        [scriptblock]$ReadmeFileSelector,
        [scriptblock]$DemFileSelector,
        [scriptblock]$OrthoSelectionModeReader,
        [scriptblock]$SupFileSelector,
        [scriptblock]$WorkflowInvoker
    )

    $workflowScript = Resolve-OrthoLauncherWorkflowPath -ScriptRoot $ScriptRoot
    $projectName = Read-OrthoLauncherRequiredValue -Prompt 'Project name' -ReadInput $ReadInput -EmptyMessage 'Project name cannot be empty.' -Trim
    $producerName = if ($ProducerSelector) { & $ProducerSelector } else { Read-OrthoLauncherProducer -ReadInput $ReadInput }
    if ([string]::IsNullOrWhiteSpace([string]$producerName)) { throw 'A producer must be selected.' }

    Write-Host ''
    Write-Host 'Use the default SOCET roots?'
    Write-Host 'Data: E:\Socet\data'
    Write-Host 'Images: E:\Socet\images'
    $useDefaultRoots = Read-OrthoLauncherYesNo -Prompt '[Y/N]' -ReadInput $ReadInput
    if ($useDefaultRoots) {
        $socetDataRoot = 'E:\Socet\data'
        $socetImagesRoot = 'E:\Socet\images'
    }
    else {
        $socetDataRoot = Read-OrthoLauncherRequiredValue -Prompt 'SocetDataRoot' -ReadInput $ReadInput -EmptyMessage 'SocetDataRoot cannot be blank.'
        $socetImagesRoot = Read-OrthoLauncherRequiredValue -Prompt 'SocetImagesRoot' -ReadInput $ReadInput -EmptyMessage 'SocetImagesRoot cannot be blank.'
    }

    $includeColor = Read-OrthoLauncherYesNo -Prompt 'Does this project include COLOR products? [Y/N]' -ReadInput $ReadInput
    $expectedImagesProjectDirectory = Join-Path $socetImagesRoot $projectName
    $expectedProjectDirectory = Join-Path $socetDataRoot $projectName
    $supSelectionMode = if ($OrthoSelectionModeReader) { & $OrthoSelectionModeReader } else { Read-OrthoLauncherSupSelectionMode -ReadInput $ReadInput }
    if ($supSelectionMode -eq 'Cancel') {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }
    $approvedSupPaths = @()
    if ($SupFileSelector) {
        $approvedSupPaths = @(& $SupFileSelector $expectedProjectDirectory $supSelectionMode)
        if ($approvedSupPaths.Count -eq 0) {
            Write-Host 'Workflow cancelled. No workflow command was run.'
            return 0
        }
        foreach ($supPath in @($approvedSupPaths)) { Assert-OrthoLauncherSupFile -Path ([string]$supPath) -ExpectedProjectDirectory $expectedProjectDirectory | Out-Null }
    }
    elseif ($supSelectionMode -eq 'Manual') {
        $approvedSupPaths = @(Select-OrthoLauncherSupFiles -ExpectedProjectDirectory $expectedProjectDirectory)
        if ($approvedSupPaths.Count -eq 0) {
            Write-Host 'Workflow cancelled. No workflow command was run.'
            return 0
        }
    }
    elseif (Test-Path -LiteralPath $expectedProjectDirectory -PathType Container) {
        $automaticSupSelection = Get-OrthoSupSelection -ProjectDirectory $expectedProjectDirectory -Method Automatic -IncludeColor:$includeColor
        if (-not $automaticSupSelection.IsValid) {
            Write-Host 'Automatic ortho SUP discovery needs review:' -ForegroundColor Yellow
            foreach ($selectionError in @($automaticSupSelection.Errors)) { Write-Host " - $selectionError" -ForegroundColor Yellow }
            if (-not (Read-OrthoLauncherYesNo -Prompt 'Open manual SUP selection instead? [Y/N]' -ReadInput $ReadInput)) {
                throw 'Automatic ortho SUP discovery was invalid and manual selection was declined.'
            }
            $supSelectionMode = 'Manual'
            $approvedSupPaths = @(Select-OrthoLauncherSupFiles -ExpectedProjectDirectory $expectedProjectDirectory)
            if ($approvedSupPaths.Count -eq 0) {
                Write-Host 'Workflow cancelled. No workflow command was run.'
                return 0
            }
        }
        else { $approvedSupPaths = @($automaticSupSelection.Files | ForEach-Object FullName) }
    }
    else {
        # Run-OrthoWorkflow performs the authoritative project check and automatic
        # discovery. This branch keeps the launcher thin and produces a clear error
        # there when an unavailable project is selected.
        Write-Host "Project directory is not available for launcher preview; automatic SUP discovery will be performed by the workflow: $expectedProjectDirectory" -ForegroundColor Yellow
    }
    if ($approvedSupPaths.Count -gt 0 -and (Test-Path -LiteralPath $expectedProjectDirectory -PathType Container)) {
        $launcherSupSelection = Get-OrthoSupSelection -ProjectDirectory $expectedProjectDirectory -SupPaths $approvedSupPaths -Method $supSelectionMode -IncludeColor:$includeColor
        if (-not $launcherSupSelection.IsValid) {
            Write-Host 'The selected ortho SUP files are not a valid workflow selection:' -ForegroundColor Yellow
            foreach ($selectionError in @($launcherSupSelection.Errors)) { Write-Host " - $selectionError" -ForegroundColor Yellow }
            Write-Host 'Workflow cancelled before conversion. Re-run the launcher to revise the SUP selection.' -ForegroundColor Yellow
            return 0
        }
        $approvedSupPaths = @($launcherSupSelection.Files | ForEach-Object FullName)
    }
    if ($approvedSupPaths.Count -gt 0) {
        Write-Host "Approved ortho SUP files ($($approvedSupPaths.Count), $supSelectionMode):"
        foreach ($supPath in @($approvedSupPaths | Sort-Object)) { Write-Host " - $(Split-Path -Leaf $supPath)" }
    }
    Write-Host ''
    Write-Host 'Select the required project README file in the Open File dialog.'
    $readmePath = if ($ReadmeFileSelector) { & $ReadmeFileSelector $expectedProjectDirectory } else { Select-OrthoLauncherReadmeFile -ExpectedProjectDirectory $expectedProjectDirectory }
    if ($null -eq $readmePath -or [string]::IsNullOrWhiteSpace([string]$readmePath)) {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }
    $readmePath = Assert-OrthoLauncherReadmeFile -Path ([string]$readmePath)
    Write-Host ''
    Write-Host 'Select the required statistics .lis file in the Open File dialog.'
    $statisticsLisPath = if ($StatisticsFileSelector) { & $StatisticsFileSelector $expectedImagesProjectDirectory } else { Select-OrthoLauncherStatisticsLisFile -ExpectedImagesProjectDirectory $expectedImagesProjectDirectory }
    if ($null -eq $statisticsLisPath -or [string]::IsNullOrWhiteSpace([string]$statisticsLisPath)) {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }
    $statisticsLisPath = Assert-OrthoLauncherStatisticsLisFile -Path ([string]$statisticsLisPath)
    Write-Host ''
    Write-Host 'Select the required DEM .dth file in the Open File dialog.'
    $demPath = if ($DemFileSelector) { & $DemFileSelector $expectedProjectDirectory } else { Select-OrthoLauncherDemFile -ExpectedProjectDirectory $expectedProjectDirectory }
    if ($null -eq $demPath -or [string]::IsNullOrWhiteSpace([string]$demPath)) {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }
    $demPath = Assert-OrthoLauncherDemFile -Path ([string]$demPath) -ExpectedProjectDirectory $expectedProjectDirectory
    $mode = Read-OrthoLauncherMode -ReadInput $ReadInput
    if ($mode -eq 'Cancel') {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }
    $modeDefinition = Get-OrthoLauncherModeDefinition -Mode $mode

    $workflowParameters = @{
        ProjectName = $projectName
        SocetDataRoot = $socetDataRoot
        SocetImagesRoot = $socetImagesRoot
        StatisticsLisPath = $statisticsLisPath
        ProducerName = $producerName
        ReadmePath = $readmePath
        DemPath = $demPath
        SupSelectionMode = $supSelectionMode
    }
    if ($approvedSupPaths.Count -gt 0) { $workflowParameters.SupPaths = @($approvedSupPaths) }
    if ($includeColor) { $workflowParameters.IncludeColor = $true }
    foreach ($parameterName in $modeDefinition.Parameters.Keys) {
        $workflowParameters[$parameterName] = $modeDefinition.Parameters[$parameterName]
    }
    if ($mode -ne 'DryRun') { $workflowParameters.EnableInteractivePreflightRetry = $true }

    Write-Host ''
    Write-Host '--------------------------------------------------'
    Write-Host 'SOCET Ortho Workflow Summary'
    Write-Host '--------------------------------------------------'
    Write-Host "Project: $projectName"
    Write-Host "Data root: $socetDataRoot"
    Write-Host "Images root: $socetImagesRoot"
    Write-Host "Statistics LIS: $statisticsLisPath"
    Write-Host "Producer: $producerName"
    Write-Host "README: $readmePath"
    Write-Host "DEM: $demPath"
    Write-Host "Ortho selection: $supSelectionMode"
    Write-Host "Approved ortho SUP files: $($approvedSupPaths.Count)"
    Write-Host "COLOR products: $(if ($includeColor) {'Yes'} else {'No'})"
    Write-Host "Mode: $($modeDefinition.Label)"
    Write-Host "Workflow script: $workflowScript"
    Write-Host '--------------------------------------------------'

    $continue = Read-OrthoLauncherYesNo -Prompt 'Continue? [Y/N]' -ReadInput $ReadInput
    if (-not $continue) {
        Write-Host 'Workflow cancelled. No workflow command was run.'
        return 0
    }

    if ($WorkflowInvoker) {
        $workflowExitCode = [int](& $WorkflowInvoker $workflowScript $workflowParameters)
    }
    else {
        & $workflowScript @workflowParameters | Out-Host
        $workflowExitCode = [int]$LASTEXITCODE
    }

    if ($workflowExitCode -eq 0) {
        Write-Host 'SOCET ortho workflow completed successfully.' -ForegroundColor Green
    }
    else {
        Write-Host "SOCET ortho workflow failed with exit code $workflowExitCode." -ForegroundColor Red
    }
    return $workflowExitCode
}

if ($MyInvocation.InvocationName -ne '.') {
    $launcherExitCode = 1
    try {
        $launcherExitCode = Invoke-OrthoWorkflowLauncher
    }
    catch {
        Write-Host "Launcher error: $($_.Exception.Message)" -ForegroundColor Red
        $launcherExitCode = 1
    }
    exit $launcherExitCode
}
