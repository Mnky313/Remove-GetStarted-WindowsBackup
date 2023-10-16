### Installs Dependencies
function Install-Dependencies {
    # Check if DotNET SQLite binaries exist
    $sqliteModule = Get-InstalledModule -Name mySQLite -ErrorAction Ignore
    if ($sqliteModule -eq $null) {
        Write-Host Installing MySQLite...
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
        Install-Module -Name MySQLite -Repository PSGallery -Confirm:$False
    }
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Confirm:$False
    Import-Module -Name MySQLite
}

# Import SQLite Binaries
Install-Dependencies

### Modifies StateRepository DB to allow uninstallation of Client.CBS
function Unlock-Package {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $package
    )
    # Grant Administrators access to StateRepository DB
    takeown /f "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" /a
    takeown /f "C:\ProgramData\Microsoft\Windows\AppRepository" /a
    icacls "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" /grant "Administrators:F"
    icacls "C:\ProgramData\Microsoft\Windows\AppRepository" /grant "Administrators:(OI)(CI)F"

    # Kill StateRepository service before tampering with DB
    Stop-Service -Name "StateRepository" -Force

    # Make backup of StateRepository DB
    Copy-Item "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd.bak"

    # Copy StateRepository DB to temp folder for modification
    Copy-Item "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" "C:\Windows\Temp\"

    # Drop Trigger & Unlock ClientCBS
    Invoke-MySQLiteQuery -Path "C:\Windows\Temp\StateRepository-Machine.srd" -Query "DROP TRIGGER IF EXISTS TRG_AFTERUPDATE_Package_SRJournal"
    Invoke-MySQLiteQuery -Path "C:\Windows\Temp\StateRepository-Machine.srd" -Query "UPDATE Package SET IsInbox = 0 WHERE PackageFullName LIKE '%$package%'"

    # Replace StateRepository DB
    Copy-Item "C:\Windows\Temp\StateRepository-Machine.srd" "C:\ProgramData\Microsoft\Windows\AppRepository\" -Confirm:$false

    # Restart StateRepository Service
    Start-Service -Name "StateRepository"
}

### Modify Package XML ###
function Remove-App-From-Package {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $app,
        [Parameter(Mandatory=$true, Position=1)]
        [string] $package
    )
    # Locate MicrosoftWindows.Client.CBS
    $xmlPath = (Get-AppxPackage -Name "*$package*").InstallLocation+"\AppxManifest.xml"
    $xml = [xml](Get-Content $xmlPath)
    # Set apps for removal
    $node = $xml.Package.Applications.Application | Where-Object Id -eq $app
    if ($node -ne $null) {
        $node.ParentNode.RemoveChild($node)
    } else {
        Write-Host "Couldn't find application in package!"
    }
    $xml.save("C:\Windows\Temp\appxmanifest.xml") 

    # Take ownership of package appxmanifest
    takeown /f (Get-AppxPackage -Name "*$package*").InstallLocation /a
    takeown /f $xmlPath /a
    icacls (Get-AppxPackage -Name "*$package*").InstallLocation /grant "Administrators:(OI)(CI)F"
    icacls $xmlPath /grant "Administrators:F"

    # Replace XML
    Copy-Item C:\Windows\Temp\appxmanifest.xml $xmlPath -Confirm:$False
}

### Remove and reinstall package
function Reload-Package {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [string] $package
    )
    Unlock-Package $package
    $xmlPath = (Get-AppxPackage -Name "*$package*").InstallLocation+"\AppxManifest.xml"
    Get-AppxPackage -Name "*$package*" | Remove-AppxPackage
    Add-AppxPackage -DisableDevelopmentMode -Register $xmlPath -ErrorAction SilentlyContinue #Sometimes install 'fails' because it's in use (however it appears to install fine so idk)

    # Restart Explorer
    taskkill /f /im "explorer.exe"
    Start-Sleep -Seconds 1
    explorer
}

Remove-App-From-Package "WebExperienceHost" "MicrosoftWindows.Client.CBS"
Remove-App-From-Package "WindowsBackup" "MicrosoftWindows.Client.CBS"
Reload-Package "MicrosoftWindows.Client.CBS"