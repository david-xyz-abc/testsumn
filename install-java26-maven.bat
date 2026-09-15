@echo off
setlocal
set "JAVA_MAVEN_UNATTENDED=0"
if /I "%~1"=="--unattended" set "JAVA_MAVEN_UNATTENDED=1"
set "JAVA_MAVEN_INSTALLER=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "try { $s = [IO.File]::ReadAllText($env:JAVA_MAVEN_INSTALLER); & ([scriptblock]::Create(($s -split '(?m)^# POWERSHELL_START\r?$',2)[1])) } catch { Write-Host $_ -ForegroundColor Red; exit 1 }"
set "INSTALL_RESULT=%ERRORLEVEL%"
if not "%INSTALL_RESULT%"=="0" echo Installation failed or administrator permission was declined.
if "%JAVA_MAVEN_UNATTENDED%"=="0" pause
exit /b %INSTALL_RESULT%
# POWERSHELL_START
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Elevate with an encoded file path so spaces and punctuation remain safe.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    if ($env:JAVA_MAVEN_UNATTENDED -eq '1') { throw 'Unattended installation requires an administrator shell.' }
    $path64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($env:JAVA_MAVEN_INSTALLER))
    $command = "`$env:JAVA_MAVEN_INSTALLER=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$path64')); try { `$s=[IO.File]::ReadAllText(`$env:JAVA_MAVEN_INSTALLER); & ([scriptblock]::Create((`$s -split '(?m)^# POWERSHELL_START\r?$',2)[1])) } catch { Write-Host `$_ -ForegroundColor Red; Read-Host 'Press Enter to close'; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $process = Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Wait -PassThru
    exit $process.ExitCode
}

$arch = $env:PROCESSOR_ARCHITEW6432
if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
if ($arch -ne 'AMD64') { throw 'This installer requires Intel/AMD x64 Windows. ARM64 and 32-bit Windows are not supported.' }
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5.1 or later is required.' }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$javaVersion = '26.0.2.1'
$mavenVersion = '3.9.16'
$javaUrl = 'https://download.java.net/java/GA/jdk26.0.2.1/3b8e6c7ec6274148a7aa15e7e7dfb53c/1/GPL/openjdk-26.0.2.1_windows-x64_bin.zip'
$mavenBase = "https://archive.apache.org/dist/maven/maven-3/$mavenVersion/binaries/apache-maven-$mavenVersion-bin.zip"
$programFiles = [Environment]::GetEnvironmentVariable('ProgramW6432')
if (-not $programFiles) { $programFiles = $env:ProgramFiles }
$root = Join-Path $programFiles 'Java-Maven'
$javaHome = Join-Path $root "jdk-$javaVersion"
$mavenHome = Join-Path $root "apache-maven-$mavenVersion"
# Staging inherits Program Files permissions instead of using a shared temp folder.
New-Item -ItemType Directory -Path $root -Force | Out-Null
$stage = Join-Path $root ('.stage-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null

function Get-VerifiedZip($url, $destination, $algorithm, $hashLength) {
    Write-Host "Downloading $url"
    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
        throw 'curl.exe is required. Use an up-to-date Windows 10 or Windows 11 installation.'
    }
    # Native curl shows download progress and stops stalled connections.
    & curl.exe --fail --location --progress-bar --connect-timeout 30 --max-time 1800 --speed-limit 1024 --speed-time 90 --retry 2 --output $destination $url
    if ($LASTEXITCODE -ne 0) { throw "Download failed (curl exit $LASTEXITCODE). Check your connection and rerun the installer." }
    Write-Host 'Download complete. Fetching and verifying checksum...'
    $hashFile = "$destination.checksum"
    & curl.exe --fail --location --silent --show-error --connect-timeout 30 --max-time 60 --retry 2 --output $hashFile "$url.$($algorithm.ToLowerInvariant())"
    if ($LASTEXITCODE -ne 0) { throw 'Could not download checksum. Installation stopped.' }
    $checksum = Get-Content -LiteralPath $hashFile -Raw
    $match = [regex]::Match($checksum, "(?i)(?<![a-f0-9])[a-f0-9]{$hashLength}(?![a-f0-9])")
    if (-not $match.Success) { throw "Invalid checksum response for $url" }
    if ((Get-FileHash -LiteralPath $destination -Algorithm $algorithm).Hash -ne $match.Value) {
        throw "Checksum mismatch for $url. Installation stopped."
    }
    Write-Host 'Checksum OK.'
}

try {
    Write-Host "Installing OpenJDK $javaVersion and Apache Maven $mavenVersion for all users."
    if (-not (Test-Path -LiteralPath $javaHome)) {
        $zip = Join-Path $stage 'java.zip'
        Get-VerifiedZip $javaUrl $zip 'SHA256' 64
        Write-Host 'Extracting Java (this may take a few minutes)...'
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'java')
        $jdk = @(Get-ChildItem -LiteralPath (Join-Path $stage 'java') -Directory)
        if ($jdk.Count -ne 1 -or -not (Test-Path (Join-Path $jdk[0].FullName 'bin\javac.exe'))) { throw 'Unexpected JDK archive contents.' }
        Move-Item -LiteralPath $jdk[0].FullName -Destination $javaHome
    }
    if (-not (Test-Path -LiteralPath $mavenHome)) {
        $zip = Join-Path $stage 'maven.zip'
        Get-VerifiedZip $mavenBase $zip 'SHA512' 128
        Write-Host 'Extracting Maven...'
        Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'maven')
        $maven = Join-Path $stage "maven\apache-maven-$mavenVersion"
        if (-not (Test-Path (Join-Path $maven 'bin\mvn.cmd'))) { throw 'Unexpected Maven archive contents.' }
        Move-Item -LiteralPath $maven -Destination $mavenHome
    }

    # Validate both tools before changing the machine environment.
    $env:JAVA_HOME = $javaHome
    $env:MAVEN_HOME = $mavenHome
    $env:Path = "$javaHome\bin;$mavenHome\bin;$env:Path"
    & "$javaHome\bin\java.exe" --version
    if ($LASTEXITCODE -ne 0) { throw 'Java verification failed.' }
    & "$javaHome\bin\javac.exe" --version
    if ($LASTEXITCODE -ne 0) { throw 'Java compiler verification failed.' }
    & "$mavenHome\bin\mvn.cmd" --version
    if ($LASTEXITCODE -ne 0) { throw 'Maven verification failed.' }

    # Read raw PATH to preserve existing %VARIABLE% references and avoid setx truncation.
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    try {
        $oldPath = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        $backup = Join-Path $root ('environment-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
        @{
            Path = $oldPath
            PathKind = [string]$key.GetValueKind('Path')
            JAVA_HOME = $key.GetValue('JAVA_HOME', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            MAVEN_HOME = $key.GetValue('MAVEN_HOME', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        } | ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding UTF8
        $bins = @("$javaHome\bin", "$mavenHome\bin")
        $rest = @($oldPath -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -notin $bins })
        $key.SetValue('JAVA_HOME', $javaHome, [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('MAVEN_HOME', $mavenHome, [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('Path', (($bins + $rest) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally { $key.Close() }

    # Notify Explorer that future applications should inherit the updated environment.
    try {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class EnvironmentNotification {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
        $result = [UIntPtr]::Zero
        [void][EnvironmentNotification]::SendMessageTimeout([IntPtr]0xffff, 0x001a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    } catch { Write-Warning 'Sign out and back in to refresh the environment.' }

    Write-Host "`nSUCCESS! Java and Maven are installed in $root" -ForegroundColor Green
    Write-Host "Previous system environment saved to $backup"
    Write-Host 'Close and reopen terminals and IDEs; sign out and back in if they still show old versions.'
    Write-Host 'Verify with: java --version, javac --version, mvn --version'
    Write-Host 'An existing per-user JAVA_HOME can override the system setting; update it if Maven uses an older Java.'
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
if ($env:JAVA_MAVEN_UNATTENDED -ne '1') { Read-Host 'Press Enter to finish' | Out-Null }
