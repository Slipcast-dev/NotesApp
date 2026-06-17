param(
    [ValidateSet('x64', 'x86', 'arm64')]
    [string]$Architecture = 'x64',

    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\dist\portable')
)

$runtimeMap = @{
    x64   = 'win-x64'
    x86   = 'win-x86'
    arm64 = 'win-arm64'
}

$runtime = $runtimeMap[$Architecture]
$projectPath = Join-Path $PSScriptRoot '..\NotesApp\NotesApp\NotesApp.csproj'
$launcherPath = Join-Path $PSScriptRoot 'Run.cmd'
$publishDir = Join-Path $OutputRoot $runtime
$zipPath = Join-Path $OutputRoot "NotesApp-$runtime-portable.zip"
$temporaryPublishDir = Join-Path $OutputRoot ".$runtime-publish"
$temporaryPackageDir = Join-Path $OutputRoot ".$runtime-package"

if (Test-Path $temporaryPublishDir) {
    Remove-Item -LiteralPath $temporaryPublishDir -Recurse -Force
}

if (Test-Path $temporaryPackageDir) {
    Remove-Item -LiteralPath $temporaryPackageDir -Recurse -Force
}

if (Test-Path $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}

New-Item -ItemType Directory -Path $temporaryPublishDir -Force | Out-Null

try {
    # Публикуем во временную папку. Готовую portable-папку заменяем только
    # после успешной сборки и проверок, поэтому ошибка publish не уничтожит
    # предыдущую рабочую версию и пользовательскую папку Data.
    dotnet publish $projectPath `
        -c Release `
        -r $runtime `
        --self-contained true `
        -p:WindowsPackageType=None `
        -p:WindowsAppSDKSelfContained=true `
        -p:WindowsAppSdkBootstrapInitialize=false `
        -p:WindowsAppSdkDeploymentManagerInitialize=false `
        -p:PublishSingleFile=false `
        -p:PublishTrimmed=false `
        -p:DebugSymbols=false `
        -p:DebugType=None `
        -o $temporaryPublishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish exited with code $LASTEXITCODE."
    }

    $bootstrapInitializer = Get-ChildItem `
        -Path (Join-Path (Split-Path $projectPath) 'obj') `
        -Filter 'MddBootstrapAutoInitializer.cs' `
        -Recurse `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*$runtime*" } |
        Select-Object -First 1

    if ($bootstrapInitializer) {
        throw (
            "Portable validation failed: framework-dependent bootstrap code was generated: " +
            $bootstrapInitializer.FullName
        )
    }

    # Кладем launcher рядом с exe, чтобы пользователь запускал портативную
    # версию двойным кликом.
    Copy-Item `
        -LiteralPath $launcherPath `
        -Destination (Join-Path $temporaryPublishDir 'Run.cmd') `
        -Force

    $dataBackup = $null
    $existingDataDir = Join-Path $publishDir 'Data'
    if (Test-Path -LiteralPath $existingDataDir) {
        # Data содержит заметки и настройки. При повторной публикации переносим
        # папку в уникальный temp-каталог и возвращаем в новую сборку.
        $dataBackup = Join-Path ([System.IO.Path]::GetTempPath()) (
            "NotesApp-Data-" + [Guid]::NewGuid().ToString('N')
        )
        Move-Item -LiteralPath $existingDataDir -Destination $dataBackup
    }

    try {
        if (Test-Path -LiteralPath $publishDir) {
            Remove-Item -LiteralPath $publishDir -Recurse -Force
        }

        Move-Item -LiteralPath $temporaryPublishDir -Destination $publishDir

        if ($dataBackup) {
            Move-Item -LiteralPath $dataBackup -Destination (Join-Path $publishDir 'Data')
            $dataBackup = $null
        }
    }
    finally {
        # Если замена папки оборвалась, не оставляем пользовательские данные
        # во временном каталоге: восстанавливаем их в portable-папку.
        if ($dataBackup -and (Test-Path -LiteralPath $dataBackup)) {
            New-Item -ItemType Directory -Path $publishDir -Force | Out-Null
            Move-Item -LiteralPath $dataBackup -Destination (Join-Path $publishDir 'Data')
        }
    }

    # Архив предназначен для переноса на другой компьютер, поэтому локальную
    # папку Data в него не включаем. В ней могут находиться личные заметки,
    # настройки и абсолютный путь выбранного пользователем хранилища.
    New-Item -ItemType Directory -Path $temporaryPackageDir -Force | Out-Null
    Get-ChildItem -LiteralPath $publishDir -Force |
        Where-Object { $_.Name -ne 'Data' } |
        Copy-Item -Destination $temporaryPackageDir -Recurse -Force

    Compress-Archive `
        -Path (Join-Path $temporaryPackageDir '*') `
        -DestinationPath $zipPath `
        -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPublishDir) {
        Remove-Item -LiteralPath $temporaryPublishDir -Recurse -Force
    }

    if (Test-Path -LiteralPath $temporaryPackageDir) {
        Remove-Item -LiteralPath $temporaryPackageDir -Recurse -Force
    }
}

Write-Host "Portable build created:"
Write-Host "  Folder: $publishDir"
Write-Host "  Zip:    $zipPath"
