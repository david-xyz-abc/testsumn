$ErrorActionPreference = 'Stop'
$expectedJava = 'C:\Program Files\Java-Maven\jdk-26.0.2.1'
$expectedMaven = 'C:\Program Files\Java-Maven\apache-maven-3.9.16'
$env:JAVA_HOME = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'Machine')
$env:MAVEN_HOME = [Environment]::GetEnvironmentVariable('MAVEN_HOME', 'Machine')
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($env:JAVA_HOME -ne $expectedJava) { throw "Wrong system JAVA_HOME: $env:JAVA_HOME" }
if ($env:MAVEN_HOME -ne $expectedMaven) { throw "Wrong system MAVEN_HOME: $env:MAVEN_HOME" }
foreach ($tool in @('java.exe', 'javac.exe', 'mvn.cmd')) {
    $resolved = (Get-Command $tool).Source
    if (-not $resolved.StartsWith('C:\Program Files\Java-Maven\')) { throw "Wrong $tool resolved: $resolved" }
}
$bins = $env:Path -split ';'
foreach ($bin in @("$expectedJava\bin", "$expectedMaven\bin")) {
    if (@($bins | Where-Object { $_ -eq $bin }).Count -ne 1) { throw "Duplicate or missing PATH entry: $bin" }
}
$javaVersion = & java.exe --version
if ($LASTEXITCODE -ne 0 -or ($javaVersion -join ' ') -notmatch '26\.0\.2\.1') { throw 'Wrong Java version.' }
$mavenVersion = & mvn.cmd --version
if ($LASTEXITCODE -ne 0 -or ($mavenVersion -join ' ') -notmatch 'Apache Maven 3\.9\.16') { throw 'Wrong Maven version.' }
$project = Join-Path $env:RUNNER_TEMP ('java-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path "$project\src\main\java" -Force | Out-Null
@'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>test</groupId><artifactId>smoke</artifactId><version>1.0</version>
  <build><plugins><plugin>
    <groupId>org.apache.maven.plugins</groupId><artifactId>maven-compiler-plugin</artifactId><version>3.14.0</version>
    <configuration><release>26</release></configuration>
  </plugin></plugins></build>
</project>
'@ | Set-Content "$project\pom.xml" -Encoding ASCII
'public class Smoke { public static void main(String[] args) { System.out.println("JAVA26_OK"); } }' | Set-Content "$project\src\main\java\Smoke.java" -Encoding ASCII
& mvn.cmd -B -ntp -f "$project\pom.xml" package
if ($LASTEXITCODE -ne 0) { throw 'Maven build failed.' }
$output = & java.exe -cp "$project\target\classes" Smoke
if ($LASTEXITCODE -ne 0 -or $output -ne 'JAVA26_OK') { throw 'Compiled application failed.' }
Write-Host 'PASS: system settings, command resolution, versions, PATH uniqueness, Java 26 compilation and execution.'
