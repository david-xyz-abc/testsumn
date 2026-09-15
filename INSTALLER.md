# Java 26 and Maven installer

Download `install-java26-maven.bat`, double-click it, and approve the administrator prompt. Requires Intel/AMD x64 Windows 10/11 with curl.exe and internet access. It installs OpenJDK 26.0.2.1 and Maven 3.9.16 into Program Files and sets system JAVA_HOME, MAVEN_HOME, and PATH. Reopen terminals afterward. Existing per-user JAVA_HOME settings may need updating.

Downloads display progress, retry transient failures, and stop stalled transfers. Checksum verification and extraction have explicit status messages. Previous system environment values are backed up under `C:\Program Files\Java-Maven`.

## Automated test

Under Actions, select **Test Windows Java and Maven installer**, then **Run workflow**. The workflow installs the tools on a Windows Server 2022 runner, checks system environment and command resolution, builds and runs a Java 26 project, then repeats installation and checks again. It does not test desktop double-click or UAC interaction on Windows 10/11.

For an already elevated shell: `install-java26-maven.bat --unattended`.
