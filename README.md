# SOCET orthorectification and DTM-product workflow (Windows PowerShell)

This project safely automates the intent of manual SOCET Steps 10.0, 10.1, and 10.2. It is deliberately written for **Windows PowerShell 5.1+ on the separate Windows SOCET computer**, even though it was developed on macOS. macOS is used only for mock-only unit tests; it is not a supported production target.

Current release metadata is `0.2.0-rc1`. The release-candidate designation is intentionally retained while deployment is expanded beyond the acceptance-test computer.

The confirmed baseline comprises two Windows PowerShell 5.1 acceptance tests: a full Briault SOCET run completed 16 sequential ortho conversions and one DEM conversion with zero exit codes, staged the exact 15 main and 24 COLOR files, and passed final staging validation; a separate real `-SkipConversions` run wrote both reports, completed JSON serialization, logged process exit, and returned to the PowerShell prompt.

No SOCET command, Windows drive, production project, or scientific product was accessed while creating this project.

## Workflow interpretation

1. **10.0 Orthorectified images.** The script validates `<SocetDataRoot>\<ProjectName>`, finds every top-level `*_o.sup`, and plans `start_socet -single ortho2isis3 <ProjectName> <SupBaseName> <SupBaseName>.cub`. It retains the manual batch workflow by generating `output_products\ortho2isis.bat` in ASCII.
2. **10.1 DEM.** The script uses `-DemName` as the `.dth` base name, auto-selects one nonzero top-level `.dth`, or safely prompts for a selection when multiple candidates exist. In a non-interactive session it uses the most recently modified nonzero candidate and records a warning. It plans `start_socet -single dem2isis3 <ProjectName> <DemBaseName> <DemBaseName>.cub`.
3. **10.2 Products.** Strict configuration rules select only the required completed-project files: data products from `<SocetDataRoot>\<ProjectName>` and `output_products` where configured, plus the project-information `.lis` from `<SocetImagesRoot>\<ProjectName>`. Selected files are copied, never moved, to the Windows Desktop staging folder `<Desktop>\<ProjectName>` with its required `COLOR` subdirectory.

## Important unresolved assumptions

- The notes say both `output_product` and `output_products`. The provisional configuration uses `output_products`.
- The notes give both `E:\Socet\data\<Project>` and `\socet\e\data\<Project>`. The parameter default is `E:\Socet\data`; no path typo was silently corrected.
- The confirmed launcher is `C:\SOCET_SET_5.6.0\bin\start_socet.bat`. `Test-WindowsEnvironment.ps1` reports whether the configured launcher resolves; it never runs it.
- The batch and DEM working-directory settings used by the current configuration were exercised successfully in the confirmed Briault Windows run. They remain configurable and should be revalidated if a colleague's SOCET installation or project layout differs.
- The completed-project structure requires 15 selected main-folder files plus one `COLOR` subdirectory. The supplied configuration requires `-IncludeColor`, a complete 24-file COLOR set, and a separate `COLOR` staging directory; it does not copy merely COLOR-like files.

## Required Windows environment

- Windows PowerShell 5.1 or PowerShell 7+
- SOCET installed and initialized so `start_socet` is available
- the confirmed launcher path (default `C:\SOCET_SET_5.6.0\bin\start_socet.bat`), overridable with `-StartSocetPath`
- Read access to the SOCET data root and target project
- Read access to the SOCET images root and corresponding images project
- Write access to the Windows Desktop (or an explicitly supplied safe Desktop-root override)
- A reviewed, resolved configuration file

The scripts do not request elevation, change execution policy, modify system environment variables, or delete/move scientific files.

## Project layout

```text
Start-OrthoWorkflow.ps1           thin interactive launcher for normal daily use
Run-OrthoWorkflow.ps1             primary workflow entry point
Test-WindowsEnvironment.ps1       read-only environment validation
Modules/OrthoWorkflow.psm1        reusable logic; external commands are centralized here
ortho-workflow.config.example.json included strict filename-rule configuration
tests/                            mock-only Pester tests and fallback harness
samples/                          illustrative, non-scientific filename lists
logs/                             timestamped workflow logs
reports/<run-id>/                 workflow-report.txt and workflow-report.json
```

The exact files required by `Run-OrthoWorkflow.ps1` at runtime are:

```text
Run-OrthoWorkflow.ps1
Modules\OrthoWorkflow.psm1
ortho-workflow.config.example.json
```

`Test-WindowsEnvironment.ps1` and `README.md` are strongly recommended in every coworker deployment, but the primary workflow does not import them. `tests/` and `samples/` are development/support material and are not required at runtime. `logs/` and `reports/` do not need to be pre-created; the workflow creates its local run directories, so the deployment folder must be writable.

## Easy interactive launcher

`Start-OrthoWorkflow.ps1` is recommended for normal daily use by coworkers. It asks for the project, source roots, COLOR choice, and one of three modes; shows the complete selection summary; and then calls `Run-OrthoWorkflow.ps1` using PowerShell parameter splatting.

```powershell
Set-Location "$env:USERPROFILE\Desktop\SOCET-OrthoWorkflow"
.\Start-OrthoWorkflow.ps1
```

No extra launcher installation or module is required. The launcher contains no scientific, conversion, product-selection, validation, staging, or reporting logic; all such behavior remains in the existing workflow. `Run-OrthoWorkflow.ps1` remains available for advanced/manual use, including explicit `-DemName`, custom configuration, `-DesktopRoot`, `-StartSocetPath`, and carefully reviewed `-Force` runs. The launcher deliberately does not offer `-Force` or DEM selection.

To use the launcher, deploy these files while preserving the `Modules` directory:

```text
Start-OrthoWorkflow.ps1
Run-OrthoWorkflow.ps1
Modules\OrthoWorkflow.psm1
ortho-workflow.config.example.json
```

## Parameters

```powershell
.\Run-OrthoWorkflow.ps1 `
  -ProjectName "Reull_Vallis_Crater_Ridges_1130E_385S" `
  -DemName "SS_DTM_Reull_Vallis" `
  -SocetDataRoot "E:\Socet\data" `
  -SocetImagesRoot "E:\Socet\images" `
  -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
  -DesktopRoot ([Environment]::GetFolderPath("Desktop")) `
  -ConfigPath .\ortho-workflow.config.example.json `
  -DryRun
```

- `ProjectName` is required and must be a single safe folder name. Traversal, rooted paths, slash characters, and unsafe characters are rejected. Spaces are allowed.
- `DemName` is optional, but when supplied must be the existing nonzero `.dth` **base name** without `.dth`; supplying it bypasses prompting. With multiple candidates, an interactive session displays name, full path, modified time, and size, then requires a numbered and confirmed choice. Interactive selection remains available during `-DryRun` because it makes no changes. Non-interactive fallback selects the latest modified candidate, resolves ties alphabetically, and records the full candidate list and warning in the report.
- `SocetDataRoot` defaults to `E:\Socet\data` and remains a Windows path even when tests run on macOS.
- `SocetImagesRoot` defaults to `E:\Socet\images`. The script resolves `<SocetImagesRoot>\<ProjectName>` with the same project-name and containment checks as the data project; it is used only for the required project-information `.lis` candidate search.
- `StartSocetPath` defaults to the confirmed `C:\SOCET_SET_5.6.0\bin\start_socet.bat` launcher and can be overridden if SOCET is installed elsewhere. It is always quoted as a launcher path; its `-single` switch and task name are not quoted.
- `DesktopRoot` is optional. If omitted, the script dynamically uses `[Environment]::GetFolderPath('Desktop')`; it must resolve to an existing folder. The final staging folder is `<DesktopRoot>\<ProjectName>`.
- `IncludeColor` is required by the supplied completed-project configuration; it validates the separate 24-file COLOR set and creates the `COLOR` staging directory.
- `SkipConversions` prevents SOCET invocation but still validates products and plans/copies only if valid.
- `DryRun` reports every command, directory creation, batch creation, Desktop-staging copy, and post-copy validation, but creates neither output nor Desktop staging directories, writes no batch file, executes no SOCET command, and copies nothing.
- `Force` is required to replace an existing planned staging file.
- `ConfirmRealExecution` is an additional deliberate safety gate for every non-dry run. This was added beyond the requested interface to prevent an accidental first production run.

## Configuration and file discovery

The supplied configuration uses generic named-capture regular expressions plus two safe runtime tokens: `{ProjectNameRegex}` and `{SelectedDemBaseNameRegex}` are replaced with escaped values selected by the workflow. Standard RAW names must begin with `SS_`, while their paired shell names omit that prefix. Both use a required `_o` structural marker; the level is captured immediately before `_o`. No literal project name, image number, year, resolution, or processing token is hardcoded.

The template requires exactly 15 selected main-folder files: 6 `.raw` (4 standard ortho, one `SS_DTM`, one `SS_FOM`), 5 `.sh` (4 ortho and 1 DEM), one final `.rep`, one selected-DEM GeoTIFF error-map `.png`, one selected-DEM GeoTIFF error-map `.gnu`, and one project-information `.lis`. It separately requires `COLOR` with exactly 12 `.raw` and 12 `.sh` files. Only files selected by valid staging rules contribute to these counts; completed-project intermediates are ignored unless they match a required rule. The `.lis` rule searches only the separate images project, considers nonzero candidates, and requires exactly one; `.txt` is not a substitute. Standard RAW/SH pairs normalize by captured `ImageId` and `Level`, excluding the RAW-only `SS_` prefix; COLOR pairs normalize by `ImageId`, `Channel`, and `Level`. The validator requires two standard image groups with two levels each, and two COLOR image groups with BG/IR/RED and two levels per channel. A file matching more than one valid rule, an unmatched pair, duplicate, missing, or extra category product is rejected.

The exact project-specific final-product rules are:

- final triangulation report: `^MST_<escaped ProjectName>\.rep$` in the data project, so per-ortho `.rep` files do not match;
- error-map PNG: `^<escaped SelectedDemBaseName>_GeoTIFF_Error_Map\.png$` in the data project, excluding Coord Maps, Weightings Maps, and PNGs for another DEM;
- GNU: `^<escaped SelectedDemBaseName>_GeoTIFF_Error_Map\.gnu$` in the data project, using the same selected DEM as the PNG;
- LIS: `^.+\.lis$` in the images project, exactly one nonzero candidate.

Configuration import rejects every malformed rule before discovery. A participating rule must have a nonempty `Name`, nonempty valid `Pattern`, `Standard` or `Color` group, positive expected count, and a supported search location. This prevents metadata/container values or unnamed rules from matching files.

Remaining filename-layout assumptions to confirm on a copied/noncritical project:

- standard products must use `SS_<image-id>_<level>_o.raw` and `<image-id>_<level>_o_ortho2isis3.sh`;
- COLOR products must use `SS_<image-id>_<BG|IR|RED>_<level>_o.raw` and the corresponding shell name without the RAW-only `SS_` prefix;
- `SS_DTM_`, `SS_FOM_`, and `_dem2isis3.sh` must match the stated fixed role markers;
- `SS_DTM`, `SS_FOM`, and DEM shell products must remain unique in the data project unless future confirmed selected-DEM naming rules allow stricter matching;
- confirmation of the folder where each class actually appears after SOCET conversion.

The sample lists demonstrate the generic parsing grammar only; they are not production project names or image identifiers.

## Batch and command behavior

`BatchFile` is the configuration default because it most closely retains the manual procedure. It emits `call "<StartSocetPath>" -single ortho2isis3 "<ProjectName>" "<BaseName>" "<BaseName>.cub"`. The launcher path and data arguments are quoted; the `-single` switch and SOCET task name are deliberately unquoted because `start_socet.bat` tests `if "%1" == "-single"`. The batch writes command markers and stops at its first nonzero command result. The DEM is invoked through the same CMD `call` rendering with the unquoted `dem2isis3` task token. The report records every intended SOCET command, its configured working directory, and the captured exit status where available.

`Direct` may be selected in configuration to run the same launcher once per ortho command through CMD `call`. All direct and batch calls use the same centralized wrapper, restore the caller location in `finally`, capture output where practical, and stop on nonzero exit status.

## Operator progress and future output completion verification

For a real batch run, the console and local log report when the batch is prepared, started, waiting, and returned, followed by the same start/wait/return messages for the DEM. They then report product validation, Desktop-plan construction, copying, post-copy validation, and final completion or failure. During `-DryRun`, these are explicitly described as actions that **would run**; no SOCET command is started.

SOCET stdout and stderr are redirected independently to temporary local files by `Start-Process -Wait -PassThru` and are available after the process returns; they are not currently streamed live. Native stderr never enters PowerShell's error stream. A zero native exit code remains successful and any stderr text is preserved and logged as a warning; a nonzero exit code fails and its stderr is logged as an error. Therefore, after a `Waiting for SOCET ... to complete` message, a long conversion may produce no further console output until the wrapper returns.

The machine-readable report is built from a fixed plain-data schema rather than serializing the live PowerShell workflow state. File and diagnostic values are reduced to explicit scalar fields. Native stdout/stderr captures are stored once under `NativeOutputCaptures` and commands reference them by `CaptureId`, avoiding duplication of the complete ortho batch output across every command. JSON is serialized with bounded depth and written to a temporary sibling file before being renamed to `workflow-report.json`. A JSON-report failure is appended to the text report and causes a controlled nonzero exit without changing validated or staged products.

`OutputCompletionVerification` in the example JSON remains an intentionally disabled design (`Enabled: false`) and is not active synchronization logic. The Windows launcher test established that `start_socet.bat` reaches its synchronous `start /b /WAIT` single-task path when `-single` and the task token are unquoted. No polling or sleep-based synchronization was added.

## Environment validation and safe rollout

Transfer the three direct-workflow runtime files listed above while preserving the `Modules` subdirectory. For normal coworker use, also include `Start-OrthoWorkflow.ps1`; for an operational deployment, include `Test-WindowsEnvironment.ps1` and this README as well. Tests and samples may be included for support, but neither production entry point requires them.

1. Open the SOCET-initialized PowerShell session.
2. Run the read-only validator when conversions are expected:

   ```powershell
   .\Test-WindowsEnvironment.ps1 `
     -ProjectName "Example_Project" `
     -SocetDataRoot "E:\Socet\data" `
     -SocetImagesRoot "E:\Socet\images" `
     -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
     -ConfigPath ".\ortho-workflow.config.example.json"
   ```

   A missing or invalid launcher is an error in this mode. For validation of an already completed project where conversions will intentionally be skipped, add `-SkipConversions`; only in that validator mode is a missing launcher nonfatal:

   ```powershell
   .\Test-WindowsEnvironment.ps1 `
     -ProjectName "Example_Project" `
     -SocetDataRoot "E:\Socet\data" `
     -SocetImagesRoot "E:\Socet\images" `
     -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
     -ConfigPath ".\ortho-workflow.config.example.json" `
     -SkipConversions
   ```

   The validator resolves the data and images project paths, reports `.lis` candidate names and sizes from the images project, resolves the Desktop dynamically, checks the intended `<Desktop>\<ProjectName>` staging path, and creates then removes one uniquely named temporary Desktop file. It never runs SOCET, modifies scientific project data, or creates the final staging directory.
3. Review `ortho-workflow.config.example.json`. Confirm the launcher, source/output folders, and configured working directories for the colleague's installation.
4. Run a dry run:

   ```powershell
   .\Run-OrthoWorkflow.ps1 `
     -ProjectName "Example_Project" `
     -SocetDataRoot "E:\Socet\data" `
     -SocetImagesRoot "E:\Socet\images" `
     -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
     -ConfigPath ".\ortho-workflow.config.example.json" `
     -IncludeColor `
     -DryRun
   ```

5. Compare the generated command text in the local report with the original manual `ortho2isis3` and `dem2isis3` commands. Confirm ProjectName, base names, `.cub` targets, and CWD before proceeding.
6. Run the full workflow only after reviewing the dry run:

   ```powershell
   .\Run-OrthoWorkflow.ps1 `
     -ProjectName "Example_Project" `
     -SocetDataRoot "E:\Socet\data" `
     -SocetImagesRoot "E:\Socet\images" `
     -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
     -ConfigPath ".\ortho-workflow.config.example.json" `
     -IncludeColor `
     -ConfirmRealExecution
   ```

7. To validate and stage an already completed project without running SOCET conversions:

   ```powershell
   .\Run-OrthoWorkflow.ps1 `
     -ProjectName "Example_Project" `
     -SocetDataRoot "E:\Socet\data" `
     -SocetImagesRoot "E:\Socet\images" `
     -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
     -ConfigPath ".\ortho-workflow.config.example.json" `
     -IncludeColor `
     -SkipConversions `
     -ConfirmRealExecution
   ```

The Briault full conversion and the separate `-SkipConversions` JSON/termination run confirm the current behavior on Windows PowerShell 5.1. A colleague's installation, permissions, project naming, and SOCET paths still require the validator and dry-run checks above.

## Reports, conflicts, and safety

Every run writes a timestamped log under `logs/` and exact filenames `workflow-report.txt` and `workflow-report.json` under a unique local `reports/<run-id>/` directory. These reports exist before any Desktop staging folder is made. They capture the data-project and images-project paths, the indexed runtime configuration-rule list, inputs, commands/CWD/exit codes, discovery results, missing/zero-byte/ambiguous files, the complete staging copy plan, `CopyPlanCanExecute`, conflict count/details, duplicate destinations, existing staging items, unexpected staging items, copies, post-copy staging validation, warnings, fatal errors, and final status. Fatal reports also include exception type, script/line/offset, position message, invoking command, and script stack trace; they never include source file contents.

Desktop staging directories are created only for a valid non-dry copy plan. Existing planned staging files stop the workflow unless `-Force` is explicitly supplied. If `<DesktopRoot>\<ProjectName>` itself exists as a file, the copy plan is always blocked and `-Force` cannot bypass it. Any extra staging file or folder outside the planned 15 main files and separate COLOR contents also stops the plan even with `-Force`, because the automation never deletes items to force a match. After copying, the staging folder is checked again for exact counts, required COLOR, nonzero sizes, expected filenames, and no extras. Sources are copied with `Copy-Item`; no source move or delete command exists in production code.

## Tests and required Pester version

Tests use generated temporary mock folders and dummy byte content only. The Pester suite is pinned to **Pester 4.10.1** and stops immediately with a clear version error if another version is loaded. Windows PowerShell's bundled Pester 3.4.0 is not compatible with the suite's parameterized `Should -Be` assertion syntax.

Install Pester 4.10.1 side-by-side for the current user; do not remove the Windows-bundled module:

```powershell
Install-Module -Name Pester -RequiredVersion 4.10.1 -Scope CurrentUser -Force -SkipPublisherCheck
```

Open a fresh Windows PowerShell 5.1 session, explicitly import the pinned version, verify it, and run the suite:

```powershell
Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -RequiredVersion 4.10.1 -Force
if ((Get-Module Pester).Version -ne [version]'4.10.1') { throw 'Pester 4.10.1 was not loaded.' }
Invoke-Pester -Script .\tests -Show All
```

If Pester 4.10.1 cannot be installed in the approved environment, the minimal fallback remains available without Pester:

```powershell
& .\tests\Invoke-FallbackTests.ps1
```

The fallback covers only core safety checks. Pester covers path validation, SUP discovery, explicit/single/interactive/non-interactive DEM selection including cancellation, ties, disappearing files, and zero-byte rejection; command/batch planning; dry-run behavior; data/images-root completed-project selection with distracting intermediate REP/PNG files; the exact 15-file main-folder validation including `.lis` rejection of `.txt`; the separate 24-file COLOR validation; zero/one/multiple collection cardinalities; malformed-rule rejection; zero-byte/missing/ambiguous files; conflicts/Force; reports; and mocked external exit codes. macOS intentionally skips real Windows command, batch, SOCET, drive, execution-policy, and storage integration testing.
