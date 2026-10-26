#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectName,
	[Parameter(Mandatory)][string]$ProducerName,
	[Parameter(Mandatory)][string]$ReadmePath,
    [string]$DemName,
    [string]$SocetDataRoot = 'E:\Socet\data',
    [string]$SocetImagesRoot = 'E:\Socet\images',
    [string]$StartSocetPath = 'C:\SOCET_SET_5.6.0\bin\start_socet.bat',
    [string]$DesktopRoot = [Environment]::GetFolderPath('Desktop'),
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'ortho-workflow.config.example.json'),
    [switch]$IncludeColor,
    [switch]$DryRun,
    [switch]$SkipConversions,
    [switch]$Force,
    [switch]$ConfirmRealExecution
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules/OrthoWorkflow.psm1') -Force

if (-not (Test-Path -LiteralPath $ReadmePath -PathType Leaf)) {
    throw "README file was not found: $ReadmePath"
}

$reportContext = Get-WorkflowReportContext -ProjectRoot $PSScriptRoot
$state = New-WorkflowState -ProjectName $ProjectName -ReportContext $reportContext -DryRun:$DryRun
$exitCode = 0

try {
    Assert-SafeProjectName -ProjectName $ProjectName | Out-Null
    if (-not $DryRun -and -not $ConfirmRealExecution) {
        throw 'Real execution is intentionally gated. Re-run with -ConfirmRealExecution only after Windows environment validation and a controlled acceptance test.'
    }
    if (-not $DryRun -and -not (Test-IsWindowsHost)) {
        throw 'Real SOCET execution is Windows-only and was blocked on this non-Windows host.'
    }

    $configuration = Import-OrthoWorkflowConfiguration -ConfigPath $ConfigPath
    $config = $configuration.Data
    $state.ConfigurationPath = $configuration.Path
    $state.ConfigurationRuleDiagnostics = @($configuration.RuleDiagnostics)
    $state.IncludeColor = [bool]$IncludeColor
    foreach ($ruleDiagnostic in $state.ConfigurationRuleDiagnostics) {
        Write-OrthoLog -State $state -Level INFO -Message "Validated product rule [$($ruleDiagnostic.Index)]: Name='$($ruleDiagnostic.Name)', Group='$($ruleDiagnostic.Group)', Count=$($ruleDiagnostic.ExpectedCount), Location='$($ruleDiagnostic.SearchLocation)'"
    }
    if ($config.OutputStructure.RequireColorDirectory -and -not $IncludeColor) {
        throw 'The configured completed-project structure requires COLOR. Re-run with -IncludeColor so the 24 COLOR files and COLOR directory are validated separately.'
    }
    $unresolved = @(Get-UnresolvedConfigurationItems -Configuration $config)
    if ($unresolved.Count -gt 0) {
        foreach ($item in $unresolved) { Write-OrthoLog -State $state -Level WARNING -Message "Unresolved configuration placeholder: $item" }
        if (-not $DryRun) { throw 'Configuration contains unresolved placeholders. Real conversion and Desktop staging are blocked until strict real filename rules are supplied.' }
    }

    Assert-ExistingDirectory -Path $SocetDataRoot -Label 'SocetDataRoot' | Out-Null
    Assert-ExistingDirectory -Path $SocetImagesRoot -Label 'SocetImagesRoot' | Out-Null
    Assert-ExistingDirectory -Path $DesktopRoot -Label 'DesktopRoot' | Out-Null
    $projectDirectory = Resolve-ContainedPath -Root $SocetDataRoot -Child $ProjectName -ChildLabel 'ProjectName'
    $imagesProjectDirectory = Resolve-ContainedPath -Root $SocetImagesRoot -Child $ProjectName -ChildLabel 'ProjectName'
    Assert-ExistingDirectory -Path $projectDirectory -Label 'Project directory' | Out-Null
    Assert-ExistingDirectory -Path $imagesProjectDirectory -Label 'SOCET images project directory' | Out-Null
    Assert-SafeLeafName -Name $config.Conversion.OutputDirectoryName -Label 'Conversion.OutputDirectoryName' | Out-Null
    $outputProductsDirectory = Resolve-ContainedPath -Root $projectDirectory -Child $config.Conversion.OutputDirectoryName -ChildLabel 'output directory name'
    $stagingDirectory = Resolve-ContainedPath -Root $DesktopRoot -Child $ProjectName -ChildLabel 'ProjectName'
    $state.SourceProjectDirectory = $projectDirectory
    $state.SourceImagesProjectDirectory = $imagesProjectDirectory
    $state.OutputProductsDirectory = $outputProductsDirectory
    $state.StagingDirectory = $stagingDirectory

    $supFiles = @(Get-OrthoSupFiles -ProjectDirectory $projectDirectory)
    $state.SupInputs = @($supFiles | ForEach-Object Name)
    if ($supFiles.Count -eq 0) { throw "No *_o.sup files were found in $projectDirectory." }
    $demSelection = Select-OrthoDemFile -ProjectDirectory $projectDirectory -DemName $DemName
    $demFile = $demSelection.File
    $state.DemSelected = $demFile.Name
    $state.DemSelectedPath = $demFile.FullName
    $state.DemSelectionMethod = $demSelection.Method
    $state.DemCandidates = @($demSelection.Candidates)
    $state.DemSelectionWarnings = @($demSelection.Warnings)
    foreach ($warning in @($demSelection.Warnings)) { Write-OrthoLog -State $state -Level WARNING -Message $warning }
    Write-OrthoLog -State $state -Level INFO -Message "Selected DEM '$($demFile.FullName)' using $($demSelection.Method)."

    $orthoWorkingDirectory = Resolve-ConfiguredWorkingDirectory -ConfigurationValue $config.Conversion.OrthoWorkingDirectory -ProjectDirectory $projectDirectory -OutputProductsDirectory $outputProductsDirectory -SettingName 'Conversion.OrthoWorkingDirectory'
    $demWorkingDirectory = Resolve-ConfiguredWorkingDirectory -ConfigurationValue $config.Conversion.DemWorkingDirectory -ProjectDirectory $projectDirectory -OutputProductsDirectory $outputProductsDirectory -SettingName 'Conversion.DemWorkingDirectory'
    $commands = @(New-OrthoCommandSpecs -ProjectName $ProjectName -SupFiles $supFiles -DemFile $demFile -OrthoWorkingDirectory $orthoWorkingDirectory -DemWorkingDirectory $demWorkingDirectory -StartSocetPath $StartSocetPath)
    $orthoCommands = @($commands | Where-Object Kind -eq 'ortho2isis3')
    $state.Commands = $commands
    foreach ($command in $commands) { Write-OrthoLog -State $state -Level INFO -Message "Planned [$($command.Kind)] from '$($command.WorkingDirectory)': $(ConvertTo-DisplayCommand $command.Program $command.Arguments)" }

    $batchPath = Join-Path $outputProductsDirectory 'ortho2isis.bat'
    if ($DryRun) {
        if ($config.Conversion.OrthoExecutionMode -eq 'BatchFile') {
            Write-OrthoLog -State $state -Level INFO -Message 'DRY-RUN would prepare ortho batch.'
            Write-OrthoLog -State $state -Level INFO -Message "DRY-RUN would start ortho batch containing $($orthoCommands.Count) conversions."
            Write-OrthoLog -State $state -Level INFO -Message 'DRY-RUN would wait for SOCET ortho conversions to complete; no SOCET command will run.'
        }
        else { Write-OrthoLog -State $state -Level INFO -Message "DRY-RUN would run $($orthoCommands.Count) direct SOCET ortho conversions sequentially; no SOCET command will run." }
        Write-OrthoLog -State $state -Level INFO -Message "DRY-RUN would create directory: $outputProductsDirectory"
        if ($config.Conversion.OrthoExecutionMode -eq 'BatchFile') { New-OrthoBatchFile -Commands $commands -BatchPath $batchPath -DryRun | Out-Null; Write-OrthoLog -State $state -Level INFO -Message "DRY-RUN would write ASCII batch file: $batchPath" }
        Write-OrthoLog -State $state -Level INFO -Message 'DRY-RUN would start DEM conversion; no SOCET command will run.'
        Write-OrthoLog -State $state -Level INFO -Message 'DRY-RUN would wait for SOCET DEM conversion to complete; no SOCET command will run.'
        foreach ($command in $commands) { $command.Status = 'DryRun' }
    }
    else {
        New-Item -ItemType Directory -Path $outputProductsDirectory -Force | Out-Null
        if ($config.Conversion.OrthoExecutionMode -eq 'BatchFile') {
            Write-OrthoLog -State $state -Level INFO -Message 'Preparing ortho batch.'
            $batch = New-OrthoBatchFile -Commands $commands -BatchPath $batchPath
            Write-OrthoLog -State $state -Level INFO -Message "Created batch file: $($batch.Path)"
        }
        elseif ($config.Conversion.OrthoExecutionMode -ne 'Direct') { throw "Unsupported Conversion.OrthoExecutionMode '$($config.Conversion.OrthoExecutionMode)'." }

        if ($SkipConversions) {
            foreach ($command in $commands) { $command.Status = 'Skipped' }
            Write-OrthoLog -State $state -Level WARNING -Message 'Conversions were skipped by -SkipConversions; existing products will still be validated.'
        }
        else {
            if ($config.Conversion.OrthoExecutionMode -eq 'BatchFile') {
                if ([string]::IsNullOrWhiteSpace($env:ComSpec)) { throw 'ComSpec is unavailable; cannot execute the generated batch file.' }
                Write-OrthoLog -State $state -Level INFO -Message "Starting ortho batch containing $($orthoCommands.Count) conversions."
                Write-OrthoLog -State $state -Level INFO -Message 'Waiting for SOCET ortho conversions to complete.'
                $batchResult = Invoke-OrthoExternalCommand -Program $env:ComSpec -ArgumentList @('/d','/c',$batch.Path) -WorkingDirectory $orthoWorkingDirectory
                Write-OrthoLog -State $state -Level INFO -Message "Ortho batch returned with exit code $($batchResult.ExitCode)."
                Write-OrthoExternalResultLog -State $state -Result $batchResult -Context 'ortho batch'
                Update-OrthoBatchResults -OrthoCommands $orthoCommands -BatchResult $batchResult
                if ($batchResult.ExitCode -ne 0) { throw "ortho2isis batch execution failed with exit code $($batchResult.ExitCode)." }
            }
            else {
                for ($index = 0; $index -lt $orthoCommands.Count; $index++) {
                    $command = $orthoCommands[$index]
                    Write-OrthoLog -State $state -Level INFO -Message "Starting direct SOCET ortho conversion $($index + 1) of $($orthoCommands.Count): $($command.Input)"
                    Write-OrthoLog -State $state -Level INFO -Message "Waiting for SOCET ortho conversion $($index + 1) of $($orthoCommands.Count) to complete."
                    $result = Invoke-CommandSpec -Command $command -UseCmdCall
                    Write-OrthoLog -State $state -Level INFO -Message "Ortho conversion $($index + 1) of $($orthoCommands.Count) returned with exit code $($result.ExitCode)."
                    Write-OrthoExternalResultLog -State $state -Result $result -Context "ortho conversion $($index + 1) of $($orthoCommands.Count)"
                    if ($result.ExitCode -ne 0) { throw "ortho2isis3 failed for $($command.Input) with exit code $($result.ExitCode)." }
                }
            }
            $demCommand = @($commands | Where-Object Kind -eq 'dem2isis3')[0]
            Write-OrthoLog -State $state -Level INFO -Message "Starting DEM conversion: $($demCommand.Input)"
            Write-OrthoLog -State $state -Level INFO -Message 'Waiting for SOCET DEM conversion to complete.'
            $demResult = Invoke-CommandSpec -Command $demCommand -UseCmdCall
            Write-OrthoLog -State $state -Level INFO -Message "DEM conversion returned with exit code $($demResult.ExitCode)."
            Write-OrthoExternalResultLog -State $state -Result $demResult -Context 'DEM conversion'
            if ($demResult.ExitCode -ne 0) { throw "dem2isis3 failed with exit code $($demResult.ExitCode)." }
        }
    }

    Write-OrthoLog -State $state -Level INFO -Message $(if ($DryRun) { 'DRY-RUN would run no conversions; validating generated products currently available.' } else { 'Validating generated products.' })
    $validation = Get-ProductValidation -ProjectDirectory $projectDirectory -OutputProductsDirectory $outputProductsDirectory -ImagesProjectDirectory $imagesProjectDirectory -ProjectName $ProjectName -SelectedDemBaseName $demFile.BaseName -Configuration $config -IncludeColor:$IncludeColor
    $state.ExpectedFiles = @($validation.Expected); $state.LocatedFiles = @($validation.Located); $state.MissingFiles = @($validation.Missing); $state.ZeroByteFiles = @($validation.ZeroByte); $state.DuplicateOrAmbiguousMatches = @($validation.Ambiguous); $state.OutputStructure = $validation.Structure; $state.StructureErrors = @($validation.StructureErrors)
    if (-not $validation.IsValid) { throw 'Required product validation failed. No transfer will be performed.' }
    Write-OrthoLog -State $state -Level INFO -Message $(if ($DryRun) { 'DRY-RUN would build Desktop staging plan.' } else { 'Building Desktop staging plan.' })
    $copyPlan = New-ProductCopyPlan -ProductValidation $validation -StagingDirectory $stagingDirectory -Force:$Force
    $state.FilesProposedForCopy = @($copyPlan.Items)
    $state.ExistingStagingConflicts = @($copyPlan.ExistingConflicts) + @($copyPlan.DuplicateTargets)
    $state.UnexpectedStagingItems = @($copyPlan.UnexpectedStagingItems)
    $state.CopyPlanCanExecute = [bool]$copyPlan.CanExecute
    $state.CopyPlanConflictCount = @($copyPlan.ConflictDetails).Count
    $state.CopyPlanConflictDetails = @($copyPlan.ConflictDetails)
    $state.CopyPlanBlockReasons = @($copyPlan.BlockReasons)
    $state.DuplicateDestinationDetails = @($copyPlan.DuplicateDestinationDetails)
    $state.ExistingStagingItems = @($copyPlan.ExistingStagingItems)
    $state.StagingDirectoryExists = [bool]$copyPlan.StagingDirectoryExists
    $state.StagingDirectoryStatus = $copyPlan.StagingDirectoryStatus
    foreach ($item in $copyPlan.Items) {
        Write-OrthoLog -State $state -Level INFO -Message "Planned copy: source='$($item.Source)' destination='$($item.StagingPath)' rule='$($item.ProductRule)' group='$($item.Group)' destinationExists=$($item.DestinationAlreadyExists) duplicateTarget=$($item.DuplicateTarget) conflict='$($item.ConflictReason)'"
    }
    Write-OrthoLog -State $state -Level INFO -Message "Desktop staging status: $($copyPlan.StagingDirectoryStatus); CopyPlanCanExecute=$($copyPlan.CanExecute); conflicts=$(@($copyPlan.ConflictDetails).Count); blockReasons='$($copyPlan.BlockReasons -join ', ')'"
    foreach ($conflict in $copyPlan.ConflictDetails) {
        Write-OrthoLog -State $state -Level WARNING -Message "Desktop staging conflict: type='$($conflict.ConflictType)' source='$($conflict.SourcePath)' destination='$($conflict.DestinationPath)' destinationExists=$($conflict.DestinationAlreadyExists) destinationType='$($conflict.DestinationItemType)' duplicateSources='$($conflict.DuplicateSources -join ', ')'"
    }
    if (-not $copyPlan.CanExecute) { throw 'Desktop staging conflicts, extras, or duplicate targets make the copy plan unsafe. Use -Force only after reviewing the report.' }
    Write-OrthoLog -State $state -Level INFO -Message $(if ($DryRun) { "DRY-RUN would copy validated products to Desktop: $stagingDirectory" } else { "Copying validated products to Desktop: $stagingDirectory" })
    $copyResult = Invoke-ProductCopyPlan -CopyPlan $copyPlan -DryRun:$DryRun -Force:$Force
    $state.FilesActuallyCopied = @($copyResult.Copied); $state.FilesSkipped = @($copyResult.Skipped)
	if (-not $DryRun) {
		$readmeFileName = [System.IO.Path]::GetFileName($ReadmePath)
		$stagedReadmePath = Join-Path $stagingDirectory $readmeFileName

		if (Test-Path -LiteralPath $stagedReadmePath) {
			throw "README staging destination already exists: $stagedReadmePath"
		}

		Copy-Item -LiteralPath $ReadmePath -Destination $stagedReadmePath

		$originalBytes = [System.IO.File]::ReadAllBytes($stagedReadmePath)

		# Preserve the line-ending style already used by the README.
		$newLine = "`r`n"

		for ($i = 0; $i -lt $originalBytes.Length; $i++) {
			if ($originalBytes[$i] -eq 10) {
				if ($i -eq 0 -or $originalBytes[$i - 1] -ne 13) {
					$newLine = "`n"
				}
				break
			}
		}

		$producerLine = "Producer: $ProducerName$newLine"
		$producerBytes = [System.Text.Encoding]::ASCII.GetBytes($producerLine)

		$newBytes = New-Object byte[] ($producerBytes.Length + $originalBytes.Length)

		[Array]::Copy(
			$producerBytes,
			0,
			$newBytes,
			0,
			$producerBytes.Length
		)

		[Array]::Copy(
			$originalBytes,
			0,
			$newBytes,
			$producerBytes.Length,
			$originalBytes.Length
		)

		[System.IO.File]::WriteAllBytes($stagedReadmePath, $newBytes)

		Write-OrthoLog -State $state -Level INFO -Message "Copied README and added producer '$ProducerName': $stagedReadmePath"
	}
	
    if ($DryRun) {
        $state.StagingValidation = [pscustomobject]@{ IsValid = $null; Status = 'DryRunNotPerformed'; Missing = @(); ZeroByte = @(); Unexpected = @(); FilenameMismatches = @(); StructureErrors = @() }
        Write-OrthoLog -State $state -Level INFO -Message "DRY-RUN would validate Desktop staging folder after copy: $stagingDirectory"
    }
    else {
        Write-OrthoLog -State $state -Level INFO -Message 'Validating the staged Desktop folder.'
        $state.StagingValidation = Test-StagedProductSet -CopyPlan $copyPlan -StagingDirectory $stagingDirectory -OutputStructure $validation.Structure -AdditionalExpectedMainFile $stagedReadmePath
        if (-not $state.StagingValidation.IsValid) { throw 'Post-copy Desktop staging validation failed. No source data was changed.' }
    }
    $state.FinalSuccess = $true
    Write-OrthoLog -State $state -Level INFO -Message $(if ($DryRun) { 'Dry-run plan completed without conversion, Desktop staging creation, or copying.' } else { 'Workflow completed successfully and Desktop staging validation passed.' })
}
catch {
    $exitCode = 1
    $failureDetail = New-WorkflowFailureDetail -ErrorRecord $_
    $state.FatalErrorDetails = @($state.FatalErrorDetails) + $failureDetail
    Write-OrthoLog -State $state -Level ERROR -Message 'Workflow failed.'
    Write-OrthoLog -State $state -Level ERROR -Message $failureDetail.Message
    foreach ($diagnosticLine in @(
        "Fatal exception type: $($failureDetail.ExceptionType)",
        "Fatal script: $($failureDetail.ScriptName)",
        "Fatal line: $($failureDetail.ScriptLineNumber); offset: $($failureDetail.OffsetInLine); function: $($failureDetail.FunctionName)",
        "Fatal position: $($failureDetail.PositionMessage)",
        "Fatal invocation command: $($failureDetail.InvocationMyCommand); invocation line: $($failureDetail.InvocationScriptLineNumber); invocation offset: $($failureDetail.InvocationOffsetInLine)",
        "Fatal stack trace: $($failureDetail.ScriptStackTrace)"
    )) { Write-OrthoLog -State $state -Level ERROR -Message $diagnosticLine }
}
finally {
    $exitCode = Complete-WorkflowReporting -State $state -ExitCode $exitCode
    Write-Host "Report: $($state.TextReportPath)"
    if (Test-Path -LiteralPath $state.JsonReportPath -PathType Leaf) { Write-Host "Machine-readable report: $($state.JsonReportPath)" }
}

try { Write-OrthoLog -State $state -Level INFO -Message 'Workflow process exiting.' }
catch { Write-Host 'Workflow process exiting.' }
exit $exitCode
