function Install-Dependencies {
    # Check if DotNET SQLite binaries exist
    $sqliteModule = Get-InstalledModule -Name mySQLite -ErrorAction Ignore
    if ($sqliteModule -eq $null) {
        Write-Host Installing MySQLite...
        Install-Module -Name MySQLite -Repository PSGallery -Confirm:$False
    }
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Confirm:$False
    Import-Module -Name MySQLite
}

function Unlock-Package {
    # Take ownership of DB
    takeown /f "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" /a
    takeown /f "C:\ProgramData\Microsoft\Windows\AppRepository" /a
    icacls "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" /grant "Administrators:F"
    icacls "C:\ProgramData\Microsoft\Windows\AppRepository" /grant "Administrators:(OI)(CI)F"

    # Kill StateRepository before tampering with DB
    Stop-Service -Name "StateRepository" -Force

    # Make backup of DB
    Copy-Item "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd.bak"

    # Copy DB to temp folder
    Copy-Item "C:\ProgramData\Microsoft\Windows\AppRepository\StateRepository-Machine.srd" "C:\Windows\Temp\"

    # Drop Trigger & Unlock ClientCBS
    Invoke-MySQLiteQuery -Path "C:\Windows\Temp\StateRepository-Machine.srd" -Query "DROP TRIGGER IF EXISTS TRG_AFTERUPDATE_Package_SRJournal"
    Invoke-MySQLiteQuery -Path "C:\Windows\Temp\StateRepository-Machine.srd" -Query "UPDATE Package SET IsInbox = 0 WHERE PackageFullName LIKE '%Client.CBS%'"

    # Replace DB
    Copy-Item "C:\Windows\Temp\StateRepository-Machine.srd" "C:\ProgramData\Microsoft\Windows\AppRepository\" -Confirm:$false

    # Restart Service
    Start-Service -Name "StateRepository"
}

# Import SQLite Binaries
Install-Dependencies

### Modify XML ###
# Locate MicrosoftWindows.Client.CBS
$CBSFolder = (Get-ChildItem C:\Windows\SystemApps\ | Where-Object Name -like *MicrosoftWindows.Client.CBS*).Name
$xmlPath = "C:\Windows\SystemApps\$CBSFolder\appxmanifest.xml"
$xml = [xml](Get-Content $xmlPath)
# Set apps for removal
$node = $xml.Package.Applications.Application | Where-Object Id -eq 'WebExperienceHost'
$node2 = $xml.Package.Applications.Application | Where-Object Id -eq 'WindowsBackup'
# Check if those apps even exist & Remove ones that do
if ($node -ne $null) {
    $node.ParentNode.RemoveChild($node)
}
if ($node2 -ne $null) {
    $node2.ParentNode.RemoveChild($node2)
}
# Save temporary XML
$xml.save("C:\Windows\Temp\appxmanifest.xml") 

# Take ownership of package appxmanifest
takeown /f "C:\Windows\SystemApps\$CBSFolder" /a
takeown /f $xmlPath /a
icacls "C:\Windows\SystemApps\$CBSFolder" /grant "Administrators:(OI)(CI)F"
icacls $xmlPath /grant "Administrators:F"

# Replace XML
Copy-Item C:\Windows\Temp\appxmanifest.xml $xmlPath -Confirm:$False

# Re-register ClientCBS
Unlock-Package
Get-AppxPackage -Name "MicrosoftWindows.Client.CBS" | Remove-AppxPackage
Add-AppxPackage -DisableDevelopmentMode -Register $xmlPath -ErrorAction SilentlyContinue #Sometimes install 'fails' because it's in use (however it appears to install fine so idk)

# Restart Explorer
taskkill /f /im "explorer.exe"
Start-Sleep -Seconds 1
explorer