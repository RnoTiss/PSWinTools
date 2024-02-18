function Invoke-ElevatePrivileges {
    <#
    .SYNOPSIS
    Elevates the privileges of the PowerShell session to run as Administrator.

    .DESCRIPTION
    Checks if the current PowerShell session is running with administrative privileges. If not, it attempts to restart the session
    with elevated privileges.

    .EXAMPLE
    Invoke-ElevatePrivileges
    This example checks the current session's privilege level and restarts it with administrative privileges if necessary.
    #>

    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "Attempting to restart with administrative privileges..."
        $currentScript = $MyInvocation.MyCommand.Definition
        Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$currentScript`"" -Verb RunAs
        exit
    }

    Write-Host "Running with administrative privileges."
}

# Example usage (Uncomment to use)
# Invoke-ElevatePrivileges

Export-ModuleMember -Function 'Invoke-ElevatePrivileges'

function AnimatedSleep {
	param(
		[int]$Seconds
	)
	$lines = 3 # Number of lines for the loading animation
	$totalTime = $Seconds * 10 # Total iterations based on tenths of seconds
	$progressPerLine = [math]::Ceiling($totalTime / $lines) # Progress steps per line

	# Initialize an array to hold the progress state of each line
	$progressArray = @()
	for ($i = 0; $i -lt $lines; $i++) {
		$progressArray += 0
	}

	for ($i = 0; $i -lt $totalTime; $i++) {
		# Calculate the current line and progress on that line
		$currentLine = [math]::Floor($i / $progressPerLine)
		$currentProgress = $i % $progressPerLine

		# Update the progress in the progress array for the current line
		$progressArray[$currentLine] = $currentProgress

		# Clear the console lines for the animation
		Clear-Host

		# Draw the updated loading bar for each line
		for ($line = 0; $line -lt $lines; $line++) {
			if ($line -le $currentLine) {
				$progress = $progressArray[$line]
				$bar = "#" * $progress
				$empty = " " * ($progressPerLine - $progress)
				Write-Host ("[" + $bar + $empty + "]")
			} else {
				Write-Host ("[" + (" " * $progressPerLine) + "]")
			}
		}

		Start-Sleep -Milliseconds 100
	}
}


function Clean-OneLevelProfileDirectory {
	param(
		[string]$Directory
	)
	try {
		# Restart the explorer.exe process
		Get-Process -Name explorer | Stop-Process -ErrorAction Inquire
		Get-Process -Name cloud-drive-ui | Stop-Process -ErrorAction SilentlyContinue
		Get-Process -Name cloud-drive-connect | Stop-Process -ErrorAction SilentlyContinue
		Get-Process -Name cloud-drive-daemon | Stop-Process -ErrorAction SilentlyContinue

		# Define the path to the profile directory and the directory name
		$profilePath = [Environment]::GetFolderPath("UserProfile")
		$dirName = $Directory

		# Construct the full paths for the original and the .old directories
		$originalDirPath = Join-Path -Path $profilePath -ChildPath $dirName
		$oldDirPath = "$originalDirPath.old"

		# Check if the original directory exists before renaming
		if (Test-Path $originalDirPath) {
			# Rename the original directory to .old
			Rename-Item -Path $originalDirPath -NewName $oldDirPath -Force -ErrorAction Inquire
		} else {
			Write-Host "The directory $originalDirPath does not exist. Exiting script."
			return
		}

		# Create a new empty directory with the original name
		New-Item -Path $originalDirPath -ItemType Directory -Force -ErrorAction Inquire

		# Copy the directory structure from the .old directory to the new one
		Copy-DirectoryStructure -SourceDir $oldDirPath -DestinationDir $originalDirPath
		
		### Empty old
		# PowerShell commands to change console color, wait, and delete a directory with verbose output
		$commands = @"
`$host.UI.RawUI.BackgroundColor = 'Red'
`$host.UI.RawUI.ForegroundColor = 'White'
Clear-Host # Clears the console to apply the new color settings
AnimatedSleep -Seconds 10
Remove-Item -Path '{0}' -Recurse -Force -Verbose
"@ -f $oldDirPath.Replace("'", "''") # Safely insert the path, escaping single quotes
		
		# Convert the commands to a single line, escaping inner double quotes
		$encodedCommands = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($commands))

		# Start a new PowerShell process with the encoded commands
		Start-Process powershell.exe -ArgumentList "-NoProfile -EncodedCommand $encodedCommands" -WindowStyle Normal
		
		####
		Start-Process explorer.exe
		AnimatedSleep -Seconds 10
		Start-Process explorer.exe $originalDirPath
} catch {
		Write-Error "An error occurred: $_"
		exit 1
	}
}

function Copy-DirectoryStructure {
	param (
		[string]$SourceDir,
		[string]$DestinationDir
	)

	Get-ChildItem -Path $SourceDir -Directory | ForEach-Object {
		$newDir = Join-Path -Path $DestinationDir -ChildPath $_.Name
		New-Item -Path $newDir -ItemType Directory -Force -ErrorAction Stop

		# Recursive call to replicate subdirectories
		# Copy-DirectoryStructure -SourceDir $_.FullName -DestinationDir $newDir
	}
}

# Call the function to start the process
# Clean-OneLevelProfileDirectory -Directory "SynoDrive"

Export-ModuleMember -Function 'Clean-OneLevelProfileDirectory'

function Invoke-ApplicationUninstaller {
    param (
        [string]$displayName
    )

    # Assuming Get-UninstallInformation function is already defined
    $uninstallInfo = Get-UninstallInformation -displayName $displayName
    $uninstallString = if ($uninstallInfo.QuietUninstallString) { $uninstallInfo.QuietUninstallString } else { $uninstallInfo.UninstallString }

    if (-not $uninstallString) {
        Write-Host "Uninstall string not found for `"$displayName`". Exiting..."
        return
    }

    # Handle uninstall string with quotes and parameters
    if ($uninstallString -match '^"(.+?)"\s*(.*)') {
        $executable = $matches[1]
        $arguments = $matches[2]
    } else {
        # Fallback for cases without quotes
        $uninstallParts = $uninstallString -split ' ', 2
        $executable = $uninstallParts[0]
        $arguments = $uninstallParts[1]
    }

    # Execute the uninstall command
    Start-Process -FilePath $executable -ArgumentList $arguments -Wait

    # Wait a moment for the uninstall to potentially complete
    Start-Sleep -Seconds 10

    # Re-check if the application is still installed
    $uninstallInfoAfter = Get-UninstallInformation -displayName $displayName
    if (-not $uninstallInfoAfter.UninstallString) {
        Write-Host "Uninstallation of `"$displayName`" completed successfully."
    } else {
        Write-Host "Error: Uninstallation of `"$displayName`" may have failed."
    }
}

function Get-UninstallInformation {
    param (
        [string]$displayName
    )
    
    # Define registry paths for 64-bit and 32-bit applications
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    foreach ($path in $paths) {
        $applications = Get-ChildItem -Path $path

        foreach ($app in $applications) {
            $appInfo = Get-ItemProperty -Path $app.PSPath
            if ($appInfo.DisplayName -eq $displayName) {
                return @{
                    DisplayName = $appInfo.DisplayName
                    UninstallString = $appInfo.UninstallString
                    QuietUninstallString = $appInfo.QuietUninstallString
                }
            }
        }
    }

    return $null
}

# Example usage (as a comment for reference):
# Invoke-ApplicationUninstaller -displayName "Synology Drive Client"
# Invoke-ApplicationUninstaller -displayName "UltraVnc"

Export-ModuleMember -Function 'Invoke-ApplicationUninstaller'

function Install-PowerShellViaWinget {
    <#
    .SYNOPSIS
    Installs Microsoft PowerShell via winget without interactive prompts.

    .DESCRIPTION
    This function utilizes the Windows Package Manager (winget) to install Microsoft PowerShell. 
    It assumes winget is installed and configured to run without interactive prompts for the user.

    .EXAMPLE
    Install-PowerShellViaWinget
    Installs the latest version of Microsoft PowerShell using winget.
    #>

    # Execute winget command to install Microsoft PowerShell
    winget install --id Microsoft.PowerShell --source winget

    Write-Host "Installation command for Microsoft PowerShell has been executed."
}

# Example usage:
# Install-PowerShellViaWinget

Export-ModuleMember -Function 'Install-PowerShellViaWinget'
