# SOCET orthorectification and DTM-product workflow (Windows PowerShell)

This project safely automates the intent of manual SOCET Steps 10.0, 10.1, and 10.2. It is deliberately written for **Windows PowerShell 5.1+ on the separate Windows SOCET computer**, even though it was developed on macOS. macOS is used only for mock-only unit tests; it is not a supported production target.

Current release metadata is `0.2.0-rc1`. The release-candidate designation is intentionally retained while deployment is expanded beyond the acceptance-test computer.

The confirmed baseline comprises two Windows PowerShell 5.1 acceptance tests: a full Briault SOCET run completed 16 sequential ortho conversions and one DEM conversion with zero exit codes, staged the exact 15 main and 24 COLOR files, and passed final staging validation; a separate real `-SkipConversions` run wrote both reports, completed JSON serialization, logged process exit, and returned to the PowerShell prompt.

No SOCET command, Windows drive, production project, or scientific product was accessed while creating this project.

## Workflow interpretation

1. **10.0 Orthorectified images.** The launcher asks whether to use automatic (default) or manual SUP selection. Automatic selection discovers top-level `*_o.sup` files; manual selection presents a native Windows multi-select review window. The approved selection, rather than a fixed resolution count, plans `start_socet -single ortho2isis3 <ProjectName> <SupBaseName> <SupBaseName>.cub` and determines the expected paired RAW/SH products. It retains the manual batch workflow by generating `output_products\ortho2isis.bat` in ASCII.
2. **10.1 DEM.** The normal launcher requires a selected project-associated `.dth` through a native Windows picker and passes its absolute path as `-DemPath`, avoiding a second text selection prompt. Direct use can instead supply `-DemName` as the `.dth` base name, auto-select one nonzero top-level `.dth`, or safely prompt when multiple candidates exist. In a non-interactive session it uses the most recently modified nonzero candidate and records a warning. It plans `start_socet -single dem2isis3 <ProjectName> <DemBaseName> <DemBaseName>.cub`.
3. **10.2 Products.** Strict configuration rules select the 15 required completed-project SOCET files: data products from `<SocetDataRoot>\<ProjectName>` and `output_products` where configured, plus the required project-information `.lis`. Normal daily use also selects a README and producer. The staged main folder contains the 15 SOCET products plus that README (16 files total); the staged README receives a `Producer: <name>` header while its source is never modified. Selected files are copied, never moved, to the Windows Desktop staging folder `<Desktop>\<ProjectName>` with its required `COLOR` subdirectory.

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
- Write access to the current Windows user's local, non-OneDrive Desktop; no custom staging location outside that Desktop is approved
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

`Start-OrthoWorkflow.ps1` is recommended for normal daily use by coworkers. Its sequence is project name, producer, source roots, COLOR choice, ortho SUP selection, project README, statistics `.lis`, project DEM `.dth`, workflow mode, and final confirmation. Automatic SUP selection is the default. Manual selection opens a checked native Windows list of discovered `*_o.sup` files, initially selected, and can add further project-associated SUP files without changing source data. The statistics dialog opens in the expected images-project directory when available; the README and DEM dialogs open in the expected data-project directory. The README and statistics files may be selected from another accessible directory. The DEM dialog allows browsing, but its selected file must be a nonzero top-level `.dth` in the selected SOCET data project so the established SOCET base-name command and project-association safeguards remain valid. Cancelling any dialog cleanly ends the launcher without running the workflow.

The native dialog requires an STA Windows PowerShell session. The normal Windows PowerShell console host is STA; if a host reports an STA error, start Windows PowerShell with `-STA` and run the launcher again.

```powershell
Set-Location "$env:USERPROFILE\Desktop\SOCET-OrthoWorkflow"
.\Start-OrthoWorkflow.ps1
```

No extra launcher installation is required; the launcher imports the bundled workflow module only to preview and pass the approved SUP set. It contains no conversion, scientific-product validation, staging, or reporting logic; those authoritative checks remain in the existing workflow. `Run-OrthoWorkflow.ps1` remains available for advanced/manual use, including explicit `-DemName`, `-DemPath`, or `-SupPaths`, custom configuration and `-StartSocetPath`. `-DesktopRoot` is retained for interface compatibility but must equal the current user's resolved Desktop. `-Force` cannot bypass Desktop preflight or allow reuse of an existing project folder. The launcher deliberately does not offer `-Force`.

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
  -ProducerName "Lenny Druelle" `
  -ReadmePath "C:\path\to\Project_README.txt" `
  -DemPath "E:\Socet\data\Reull_Vallis_Crater_Ridges_1130E_385S\SS_DTM_Reull_Vallis.dth" `
  -SocetDataRoot "E:\Socet\data" `
  -SocetImagesRoot "E:\Socet\images" `
  -StartSocetPath "C:\SOCET_SET_5.6.0\bin\start_socet.bat" `
  -DesktopRoot ([Environment]::GetFolderPath("Desktop")) `
  -ConfigPath .\ortho-workflow.config.example.json `
  -DryRun
```

- `ProjectName` is required and must be a single safe folder name. Traversal, rooted paths, slash characters, and unsafe characters are rejected. Spaces are allowed.
- `ProducerName` and `ReadmePath` are required for direct/manual invocation. The launcher supplies both: it presents the established five-producer menu (Lenny Druelle, Patricio Santos, Chloe Billet, Luke Meier, and Alexander Burchuladze) and uses a native picker for the README. README files may use any existing readable filename/extension supported by the original workflow.
- `DemPath` is optional and is used by the normal launcher. It must be an existing, nonzero `.dth` file directly inside `<SocetDataRoot>\<ProjectName>`; its absolute path is validated, recorded, and used to derive the existing DEM base-name command arguments. `DemName` remains supported for direct/manual use and must be the existing nonzero `.dth` **base name** without `.dth`. Supplying either explicit value bypasses prompting; supplying both is rejected. Without either value, multiple candidates use the existing numbered text prompt when interactive, or the non-interactive latest-modified fallback with a warning. Interactive selection remains available during `-DryRun` because it makes no changes.
- `SupPaths` is an optional list of approved absolute `*_o.sup` paths for direct/manual invocation. Every selected SUP must be a top-level file in `<SocetDataRoot>\<ProjectName>`. If omitted, the workflow automatically discovers top-level SUP files. `SupSelectionMode` records whether the approved selection was `Automatic` or `Manual`; it defaults to `Automatic`.
- `SocetDataRoot` defaults to `E:\Socet\data` and remains a Windows path even when tests run on macOS.
- `SocetImagesRoot` defaults to `E:\Socet\images`. Without `-StatisticsLisPath`, the script resolves `<SocetImagesRoot>\<ProjectName>` with the same project-name and containment checks as the data project and discovers the required project-information `.lis` there. Normal launcher use always supplies the selected `.lis` path. When `-StatisticsLisPath` is supplied, it must be an existing nonzero `.lis` file but may be outside the images root.
- `StatisticsLisPath` is optional for advanced/manual invocation. It is normally supplied by `Start-OrthoWorkflow.ps1`; it overrides only the project-information `.lis` discovery source and is recorded in the reports.
- `StartSocetPath` defaults to the confirmed `C:\SOCET_SET_5.6.0\bin\start_socet.bat` launcher and can be overridden if SOCET is installed elsewhere. It is always quoted as a launcher path; its `-single` switch and task name are not quoted.
- `DesktopRoot` is optional. If omitted, the script dynamically uses `[Environment]::GetFolderPath('Desktop')`. Any explicit value must equal that location. The Desktop must exist on a ready local fixed drive, without OneDrive/network redirection or reparse-point ancestors. The final staging folder remains `<Current User Desktop>\<ProjectName>`.
- `IncludeColor` is required by the supplied completed-project configuration; it validates the separate 24-file COLOR set and creates the `COLOR` staging directory.
- `SkipConversions` prevents SOCET invocation but still validates products and plans/copies only if valid.
- `DryRun` reports every command, directory creation, batch creation, Desktop-staging copy, and post-copy validation, but creates neither output nor Desktop staging directories, writes no batch file, executes no SOCET command, and copies nothing.
- `Force` is retained for compatibility with lower-level copy planning, but **cannot bypass the workflow preflight**. Full Workflow and Existing Products require an absent project staging folder, even if an existing folder is empty. Manually move or rename it before retrying; the workflow never does that for you.
- `EnableInteractivePreflightRetry` is optional and defaults off for direct execution. The launcher enables it for Full Workflow and Existing Products only. When an ordinary verified Desktop project folder exists, an interactive operator can manually move/rename it, press **R** to repeat the complete safety check, or **C** to cancel and save both reports. Inputs are retained. Unsafe paths never offer retry; noninteractive sessions fail without reading input. Dry Run never prompts, even if this switch is supplied. The immediate pre-copy check remains noninteractive and authoritative.
- `ConfirmRealExecution` is an additional deliberate safety gate for every non-dry run. This was added beyond the requested interface to prevent an accidental first production run.

## Configuration and file discovery

The supplied configuration uses generic named-capture regular expressions plus two safe runtime tokens: `{ProjectNameRegex}` and `{SelectedDemBaseNameRegex}` are replaced with escaped values selected by the workflow. Standard RAW names must begin with `SS_`, while their paired shell names omit that prefix. Both use a required `_o` structural marker; the level is captured immediately before `_o`. No literal project name, image number, year, resolution, or processing token is hardcoded.

The template's legacy completed-project example has 15 selected main-folder SOCET files: 6 `.raw` (4 standard ortho, one `SS_DTM`, one `SS_FOM`), 5 `.sh` (4 ortho and 1 DEM), one final `.rep`, one selected-DEM GeoTIFF error-map `.png`, one selected-DEM GeoTIFF error-map `.gnu`, and one project-information `.lis`; its COLOR example has 12 `.raw` and 12 `.sh` files. When a SUP selection is approved, however, standard and COLOR ortho RAW/SH counts are derived from the selected files, so valid projects may use additional or unequal resolution sets such as 25cm, 50cm, 1m, and 2m. The selected README is a required supporting input rather than a SOCET product; it is added only to the staged main folder. The staged README retains its original filename and byte content after a single ASCII `Producer: <name>` line using its existing newline style. Only products corresponding to approved SUP files contribute to the ortho counts; completed-project outputs associated with unselected SUP files are ignored. Without an explicit selection, the `.lis` rule searches the separate images project, considers nonzero candidates, and requires exactly one; an explicitly selected nonzero `.lis` takes its place. `.txt` is not a substitute. Standard RAW/SH pairs normalize by captured `ImageId` and `Level`, excluding the RAW-only `SS_` prefix; COLOR pairs normalize by `ImageId`, `Channel`, and `Level`. A file matching more than one valid rule, an unmatched selected pair, duplicate, missing, or conflicting selected product is rejected.

The exact project-specific final-product rules are:

- final triangulation report: `^MST_<escaped ProjectName>\.rep$` in the data project, so per-ortho `.rep` files do not match;
- error-map PNG: `^<escaped SelectedDemBaseName>_GeoTIFF_Error_Map\.png$` in the data project, excluding Coord Maps, Weightings Maps, and PNGs for another DEM;
- GNU: `^<escaped SelectedDemBaseName>_GeoTIFF_Error_Map\.gnu$` in the data project, using the same selected DEM as the PNG;
- LIS: `^.+\.lis$`; without an explicit selection it is discovered in the images project and must have exactly one nonzero candidate. With `-StatisticsLisPath`, that selected nonzero `.lis` is validated against the same rule and copied from its selected absolute path.

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

   The validator resolves the data and images project paths, reports `.lis` candidate names and sizes from the images project, and applies the same Desktop preflight as the workflow. Only if preflight passes does it create then remove one uniquely named temporary Desktop file. An existing destination is an error even with `-Force`. It never runs SOCET, modifies scientific project data, or creates the final staging directory.
3. Review `ortho-workflow.config.example.json`. Confirm the launcher, source/output folders, and configured working directories for the colleague's installation.
4. Run a dry run:

   ```powershell
   .\Run-OrthoWorkflow.ps1 `
     -ProjectName "Example_Project" `
     -ProducerName "Lenny Druelle" `
     -ReadmePath "C:\path\to\Project_README.txt" `
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
     -ProducerName "Lenny Druelle" `
     -ReadmePath "C:\path\to\Project_README.txt" `
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
     -ProducerName "Lenny Druelle" `
     -ReadmePath "C:\path\to\Project_README.txt" `
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

Desktop staging directories are created only for a valid non-dry copy plan. **New preflight safety policy:** before any conversion or batch-file write, both Full Workflow and Existing Products reject an existing project destination (file or directory, including an empty directory), even with `-Force`. They also reject a custom Desktop root, UNC/network Desktop, OneDrive Desktop, non-fixed/unavailable drive, or symbolic-link/junction/reparse-point component. Inspection walks existing destination components from the drive root down and fails closed when validation is unreliable. It does not alter source roots or SOCET intermediate-output locations.

The same check runs again immediately before copying, so a destination appearing or being redirected during conversion blocks staging. Copy-plan conflict checks and final exact staged-folder validation are retained. No automatic alternate folder, merge, deletion, or rename is performed. Sources are copied with `Copy-Item`; no source move or delete command exists in production code.

**Interactive retry:** the launcher now offers `[R] Retry` / `[C] Cancel` at early preflight only for a normal existing project folder. No conversion, batch write, or staging occurs while waiting. Each Retry reruns all Desktop checks and appends the result to `DesktopPreflight` in the usual reports. An unsafe result stops immediately; Cancel records a failure and returns nonzero through normal reporting. Direct automation still fails immediately unless interactive retry is explicitly enabled and interactive input is available. Nothing is automatically moved or renamed.

Dry Run records `DesktopPreflight` findings in the usual TXT/JSON reports and continues conversion/product/copy planning where safe, even when a normal existing folder blocks execution. If the destination path itself is unsafe or unverifiable, destination inspection is skipped after source-product validation. Blocked diagnostic runs return nonzero with `Success: False`; this does not mean any conversion or copy ran. Local logs/reports are still written, but no batch, scientific output, or staging products are written. On macOS the Windows Desktop cannot be verified, so preflight deliberately reports blocked; use fixture-only unit tests for development.

### Windows TEST acceptance for Desktop preflight

Use a copied/noncritical SOCET project and the TEST installation only. Run the pinned Pester suite first (below); it mocks the Desktop in disposable test deployments, never your real Desktop. Then:

1. With `<Desktop>\<ProjectName>` absent, run Dry Run and confirm preflight is safe and all existing product-selection results remain correct.
2. Create an empty project-named Desktop folder yourself. Dry Run must retain planned commands and copy mappings without a retry prompt, report that real execution is blocked, save both reports, and return nonzero. In the launcher, Full Workflow and Existing Products offer Retry/Cancel before any batch write or conversion: retry once without changing the folder (prompt repeats), then manually move/rename it and retry (workflow resumes without reselecting inputs). Separately test Cancel and verify both failure reports. Direct invocation without retry opt-in must still fail immediately, even with `-Force`.
3. In temporary fixtures, test a junction/symbolic-link ancestor, custom root, network Desktop, OneDrive Desktop, inaccessible path, and a destination that appears between preflight and copying. All must block. Do not create test junctions on scientific storage.
4. With an approved local Desktop and absent destination, repeat Existing Products mode; confirm producer-header behavior, dynamic main/COLOR counts, both reports, and return to prompt. Only then repeat a controlled full-run acceptance test.

Remaining limitation: two checks narrow but do not eliminate filesystem race conditions. Another process with write permission could change a directory between the final check and a file operation. Also, a local fixed drive is not proof that no third-party backup/sync agent monitors it; unknown sync software is not automatically identified. The Desktop preflight baseline has passed the reported Windows PowerShell 5.1 existing-folder mode tests and free-destination Existing Products staging test. The new interactive retry still needs Windows acceptance; those earlier results do not validate the new interaction.

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
