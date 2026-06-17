[CmdletBinding()]
param(
    [string]$RootDir,
    [int]$StartupProbeSeconds = 8
)

$ErrorActionPreference = 'Stop'

if (-not $RootDir) {
    $RootDir = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Show-LaunchError {
    param(
        [string]$Title,
        [string]$Message
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            $Title,
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        # Keep a console fallback so failures remain visible even if GUI APIs are unavailable.
        Write-Host $Title
        Write-Host $Message
    }
}

function Invoke-PortablePublish {
    param(
        [string]$PublishScript
    )

    if (-not (Test-Path -LiteralPath $PublishScript)) {
        throw "Publish script not found: $PublishScript"
    }

    & $PublishScript
    if ($LASTEXITCODE -ne 0) {
        throw "Portable publish exited with code $LASTEXITCODE."
    }
}

try {
    $publishScript = Join-Path $RootDir 'Tools\PublishPortable.ps1'
    $portableDir = Join-Path $RootDir 'dist\portable\win-x64'
    $portableExe = Join-Path $portableDir 'NotesApp.exe'

    # Build a fresh portable copy first so this launcher never falls back to Debug.
    Invoke-PortablePublish -PublishScript $publishScript

    if (-not (Test-Path -LiteralPath $portableExe)) {
        Show-LaunchError `
            -Title 'NotesApp launch failed' `
            -Message (
                ("After publishing, the file '{0}' was not found.`n`n" -f $portableExe) +
                'Portable build completed, but the expected executable is missing.'
            )
        exit 1
    }

    # Запускаем проверенную self-contained сборку и даем ей короткое время
    # старта. Установка Windows App Runtime для portable-версии не требуется.
    $process = Start-Process -FilePath $portableExe -WorkingDirectory $portableDir -PassThru
    Start-Sleep -Seconds $StartupProbeSeconds

    if ($process.HasExited) {
        Show-LaunchError `
            -Title 'NotesApp launch failed' `
            -Message (
                "NotesApp exited immediately.`n`n" +
                "The portable package is self-contained, so installing Windows App Runtime should not be required.`n`n" +
                ("Open '{0}\Run.cmd' or '{1}' directly. " -f $portableDir, $portableExe) +
                'If the problem repeats, check Data\startup-error.log.'
            )
        exit 1
    }
}
catch {
    Show-LaunchError `
        -Title 'NotesApp launch failed' `
        -Message (
            "Failed to launch NotesApp.`n`n" +
            "Reason: $($_.Exception.Message)`n`n" +
            'Try republishing the portable build with Tools\PublishPortable.ps1.'
        )
    exit 1
}
