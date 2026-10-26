#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:OrthoLauncherScriptRoot = $PSScriptRoot

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

function Get-OrthoLauncherModeDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('DryRun','FullWorkflow','ExistingProducts')][string]$Mode)

    switch ($Mode) {
        'DryRun' { return [pscustomobject]@{ Label='Dry run'; Parameters=@{ DryRun=$true } } }
        'FullWorkflow' { return [pscustomobject]@{ Label='Full workflow'; Parameters=@{ ConfirmRealExecution=$true } } }
        'ExistingProducts' { return [pscustomobject]@{ Label='Existing products only'; Parameters=@{ SkipConversions=$true; ConfirmRealExecution=$true } } }
    }
}

function Invoke-OrthoWorkflowLauncher {
    [CmdletBinding()]
    param(
        [string]$ScriptRoot = $script:OrthoLauncherScriptRoot,
        [scriptblock]$ReadInput = { param($Prompt) Read-Host -Prompt $Prompt },
        [scriptblock]$WorkflowInvoker
    )

    $workflowScript = Resolve-OrthoLauncherWorkflowPath -ScriptRoot $ScriptRoot
    $projectName = Read-OrthoLauncherRequiredValue -Prompt 'Project name' -ReadInput $ReadInput -EmptyMessage 'Project name cannot be empty.' -Trim

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

	Write-Host ''
	Write-Host 'Select producer:'
	Write-Host '1) Lenny Druelle'
	Write-Host '2) Patricio Santos'
	Write-Host '3) Chloe Billet'
	Write-Host '4) Luke Meier'
	Write-Host '5) Alexander Burchuladze'

	while ($true) {
		$producerChoice = ([string](& $ReadInput 'Who is the producer?')).Trim()

		switch ($producerChoice) {
			'1' { $producerName = 'Lenny Druelle' }
			'2' { $producerName = 'Patricio Santos' }
			'3' { $producerName = 'Chloe Billet' }
			'4' { $producerName = 'Luke Meier' }
			'5' { $producerName = 'Alexander Burchuladze' }
			default {
				Write-Host 'Please choose 1-5.' -ForegroundColor Yellow
				continue
			}
		}

		$confirmProducer = Read-OrthoLauncherYesNo -Prompt "Confirm producer name: $producerName [Y/N]" -ReadInput $ReadInput

		if ($confirmProducer) {
			break
		}
	}
	Write-Host ''
	$readmePath = Read-OrthoLauncherRequiredValue `
		-Prompt 'Path to project README' `
		-ReadInput $ReadInput `
		-EmptyMessage 'README path cannot be empty.' `
		-Trim

	$readmePath = $readmePath.Trim('"')

	if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
		throw "README file was not found: $readmePath"
	}	

	$mode = Read-OrthoLauncherMode -ReadInput $ReadInput
	if ($mode -eq 'Cancel') {
		Write-Host 'Workflow cancelled. No workflow command was run.'
		return 0
	}
	$modeDefinition = Get-OrthoLauncherModeDefinition -Mode $mode

    $workflowParameters = @{
        ProjectName = $projectName
		ProducerName = $producerName
		ReadmePath = $readmePath
        SocetDataRoot = $socetDataRoot
        SocetImagesRoot = $socetImagesRoot
    }
    if ($includeColor) { $workflowParameters.IncludeColor = $true }
    foreach ($parameterName in $modeDefinition.Parameters.Keys) {
        $workflowParameters[$parameterName] = $modeDefinition.Parameters[$parameterName]
    }

    Write-Host ''
    Write-Host '--------------------------------------------------'
    Write-Host 'SOCET Ortho Workflow Summary'
    Write-Host '--------------------------------------------------'
    Write-Host "Project: $projectName"
	Write-Host "Producer: $producerName"
    Write-Host "Data root: $socetDataRoot"
    Write-Host "Images root: $socetImagesRoot"
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
