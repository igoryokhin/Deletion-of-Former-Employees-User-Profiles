function Execute-StartCommands {
    $ErrorActionPreference = "Stop"
    $cred = Get-Credential

    $regions = @(
        "OU=Computers,OU=Region1,DC=corp,DC=domain,DC=com",
        "OU=Computers,OU=Region2,DC=corp,DC=domain,DC=com",
        "OU=Computers,OU=Region3,DC=corp,DC=domain,DC=com",
        "OU=Computers,OU=Region4,DC=corp,DC=domain,DC=com",
        "OU=Computers,OU=Region5,DC=corp,DC=domain,DC=com"
        # Add more regions as needed
    )

    # Display regions for selection
    Write-Host "Select regions for processing:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $regions.Count; $i++) {
        $color = if ($i % 2 -eq 0) { 'White' } else { 'Gray' }
        Write-Host "$($i + 1). $($regions[$i])" -ForegroundColor $color
    }

    # User input
    $selectedRegions = Read-Host "Enter region numbers separated by commas (e.g., 1,3,5), or 'all' to select all"

    if ($selectedRegions -eq "all") {
        $selectedRegions = 1..$regions.Count
    } else {
        $selectedRegions = $selectedRegions -split ',' | ForEach-Object { [int]$_ }
    }

    $selectedRegions = $selectedRegions | Where-Object { $_ -ge 1 -and $_ -le $regions.Count }

    Write-Host "Regions selected: $($selectedRegions.Count)" -ForegroundColor Green

    $disabledUsers = @()
    $disabledUserDetails = @()
    $disabledUserLogins = @()
    $activeComputersPool = @()
    $totalOnline = 0
    $totalOffline = 0

    if (-not (Check-InstallModule -moduleName "ActiveDirectory")) {
        Write-Host "ActiveDirectory module is not installed. Script cannot proceed." -ForegroundColor Red
        return
    }

    Write-Host "Retrieving list of disabled accounts..." -ForegroundColor Yellow
    try {
        # Get details of disabled users
        $disabledUsers = Get-ADUser -Filter {Enabled -eq $false -and DisplayName -like "*terminated*"} -Properties SamAccountName, DisplayName, LastLogonDate |
                         Select-Object SamAccountName, DisplayName, LastLogonDate

        # Extract logins in lowercase
        $disabledUserLogins = $disabledUsers | Select-Object -ExpandProperty SamAccountName | ForEach-Object { $_.ToLower() }
        $disabledUserDetails = $disabledUsers

        Write-Host "Disabled accounts found: $($disabledUsers.Count)" -ForegroundColor Green
        Write-Host "User list:" -ForegroundColor Cyan
        foreach ($user in $disabledUsers) {
            Write-Host " - Login: $($user.SamAccountName), Name: $($user.DisplayName), Last Logon: $($user.LastLogonDate)" -ForegroundColor White
        }
    } catch {
        Write-Host "Error retrieving disabled users: $_" -ForegroundColor Red
        return
    }

    # Select deletion mode
    $deleteChoice = Read-Host "Choose deletion mode: (1) Bulk deletion, (2) Selective deletion"

    foreach ($regionIndex in $selectedRegions) {
        $region = $regions[$regionIndex - 1]
        Write-Host "Searching for computers in region: $region" -ForegroundColor Yellow

        try {
            $computers = Get-ADComputer -Filter * -SearchBase $region | Select-Object -ExpandProperty Name

            if ($computers.Count -eq 0) {
                Write-Host "No computers found in region ${region}." -ForegroundColor Red
                continue
            }

            Write-Host "Computers found in region ${region}: $($computers.Count)" -ForegroundColor Green

            foreach ($computer in $computers) {
                $isOnline = Test-Connection -ComputerName $computer -Count 1 -Quiet
                if ($isOnline) {
                    Write-Host "Computer $computer is online." -ForegroundColor Green
                    $activeComputersPool += $computer
                    $totalOnline++
                } else {
                    Write-Host "Computer $computer is offline." -ForegroundColor Red
                    $totalOffline++
                }
            }
        } catch {
            Write-Host "Error processing region ${region}: $_" -ForegroundColor Red
        }
    }

    Write-Host "Active PCs: $totalOnline" -ForegroundColor Cyan
    Write-Host "Inactive PCs: $totalOffline" -ForegroundColor Cyan

    foreach ($activeComputer in $activeComputersPool) {
        try {
            Write-Host "Checking and deleting user folders on PC: $activeComputer..." -ForegroundColor Yellow

            Invoke-Command -ComputerName $activeComputer -Credential $cred -ScriptBlock {
                param ($disabledUsersList, $disabledUsersDetails, $deleteChoice)

                $userFoldersPath = "C:\Users"
                Write-Host "Scanning folders in $userFoldersPath on PC: $env:COMPUTERNAME..." -ForegroundColor Cyan
                $folders = Get-ChildItem -Path $userFoldersPath -Directory

                $foldersToDelete = @()

                foreach ($folder in $folders) {
                    $folderName = $folder.Name.ToLower()
                    Write-Host "Found folder $folderName on PC: $env:COMPUTERNAME." -ForegroundColor Yellow

                    $matchingUser = $disabledUsersDetails | Where-Object { $_.SamAccountName -ieq $folderName }

                    if ($matchingUser) {
                        $userDisplayName = $matchingUser.DisplayName
                        $lastLogonDate = $matchingUser.LastLogonDate

                        $dateDiff = (Get-Date) - $lastLogonDate
                        if ($dateDiff.Days -gt 30) {
                            Write-Host "Folder $folderName matches disabled user ($userDisplayName, Last Logon: $lastLogonDate)."
                            $foldersToDelete += $folder
                        } else {
                            Write-Host "Last logon for $folderName was less than 30 days ago. Skipping." -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "Folder $folderName does not match any disabled users. Skipping." -ForegroundColor Gray
                    }
                }

                if ($deleteChoice -eq '1') {
                    foreach ($folder in $foldersToDelete) {
                        Write-Host "Attempting to delete folder $($folder.Name) on PC: $env:COMPUTERNAME..." -ForegroundColor Cyan
                        try {
                            Remove-Item -Path $folder.FullName -Recurse -Force
                            Write-Host "Folder $($folder.Name) successfully deleted on PC: $env:COMPUTERNAME." -ForegroundColor Green
                        } catch {
                            Write-Host "Failed to delete folder $($folder.Name) on PC: $env:COMPUTERNAME. Error: $_" -ForegroundColor Red
                        }
                    }
                } elseif ($deleteChoice -eq '2') {
                    foreach ($folder in $foldersToDelete) {
                        $confirmation = Read-Host "Do you want to delete folder $($folder.Name) on PC $env:COMPUTERNAME? (Y/N)"
                        if ($confirmation -eq 'Y') {
                            Write-Host "Attempting to delete folder $($folder.Name) on PC: $env:COMPUTERNAME..." -ForegroundColor Cyan
                            try {
                                Remove-Item -Path $folder.FullName -Recurse -Force
                                Write-Host "Folder $($folder.Name) successfully deleted on PC: $env:COMPUTERNAME." -ForegroundColor Green
                            } catch {
                                Write-Host "Failed to delete folder $($folder.Name) on PC: $env:COMPUTERNAME. Error: $_" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "Folder $($folder.Name) on PC $env:COMPUTERNAME not deleted." -ForegroundColor Gray
                        }
                    }
                }
            } -ArgumentList $disabledUserLogins, $disabledUserDetails, $deleteChoice
        } catch {
            Write-Host "Script execution failed on PC ${activeComputer}: $_" -ForegroundColor Red
        }
    }
}
