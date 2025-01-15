function Check-InstallModule {
    param (
        [string]$moduleName
    )

    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Host "Module ${moduleName} not found, attempting to install..." -ForegroundColor Red
        try {
            Install-Module -Name $moduleName -Force -Scope CurrentUser
        } catch {
            Write-Host "Failed to install module ${moduleName}: $_" -ForegroundColor Red
            return $false
        }
    }
    return $true
}

function Exe-StartCommands {
    $ErrorActionPreference = "Stop"
    $cred = Get-Credential

    # Specify the region (OU) here where the computers are located
    $regions = @(
        # Example: "OU=Computers,OU=Departments,OU=YOUR_COMPANY,DC=corp,DC=COMPANY,DC=com"
        # Replace with the appropriate Distinguished Name (DN) for your environment
    )

    $disabledUsers = @()
    $activeComputersPool = @()
    $totalOnline = 0
    $totalOffline = 0

    if (-not (Check-InstallModule -moduleName "ActiveDirectory")) {
        Write-Host "ActiveDirectory module not installed. Script cannot continue." -ForegroundColor Red
        return
    }

    Write-Host "Fetching list of disabled user accounts..." -ForegroundColor Yellow
    try {
        $disabledUsers = Get-ADUser -Filter {Enabled -eq $false -and DisplayName -like "*fired*"} | Select-Object -ExpandProperty SamAccountName
        $disabledWithKeyword = $disabledUsers | Where-Object { $_ -match "fired" }
        Write-Host "Found disabled users: $($disabledUsers.Count)" -ForegroundColor Green
        Write-Host "Of which have 'fired' in the name: $($disabledWithKeyword.Count)" -ForegroundColor Cyan
    } catch {
        Write-Host "Error fetching disabled users: $_" -ForegroundColor Red
        return
    }

    foreach ($region in $regions) {
        Write-Host "Searching for computers in region: $region" -ForegroundColor Yellow

        try {
            $computers = Get-ADComputer -Filter * -SearchBase $region | Select-Object -ExpandProperty Name

            if ($computers.Count -eq 0) {
                Write-Host "No computers found in region ${region}." -ForegroundColor Red
                continue
            }

            Write-Host "Found computers in region ${region}: $($computers.Count)" -ForegroundColor Green

            $jobs = @()
            foreach ($computer in $computers) {
                $jobs += Start-Job -ScriptBlock {
                    param ($computerName)
                    if (Test-Connection -ComputerName $computerName -Count 1 -Quiet) {
                        [PSCustomObject]@{
                            Computer = $computerName
                            Status   = "Online"
                        }
                    } else {
                        [PSCustomObject]@{
                            Computer = $computerName
                            Status   = "Offline"
                        }
                    }
                } -ArgumentList $computer
            }

            $results = $jobs | ForEach-Object {
                $_ | Wait-Job | Receive-Job
                Remove-Job -Job $_ -Force
            }

            foreach ($result in $results) {
                if ($result.Status -eq "Online") {
                    $activeComputersPool += $result.Computer
                    $totalOnline++
                } else {
                    $totalOffline++
                }
            }

        } catch {
            Write-Host "Error processing region ${region}: $_" -ForegroundColor Red
        }
    }

    Write-Host "Active PCs count: $totalOnline" -ForegroundColor Cyan
    Write-Host "Inactive PCs count: $totalOffline" -ForegroundColor Cyan

    foreach ($activeComputer in $activeComputersPool) {
        try {
            Write-Host "Checking and deleting user folders on PC: $activeComputer..." -ForegroundColor Yellow

            Invoke-Command -ComputerName $activeComputer -Credential $cred -ScriptBlock {
                param ($disabledUsersList)

                $userFoldersPath = "C:\Users"
                foreach ($folder in Get-ChildItem -Path $userFoldersPath -Directory) {
                    $userName = $folder.Name
                    Write-Host "Found folder $userName on PC: $env:COMPUTERNAME..." -ForegroundColor Cyan

                    if ($disabledUsersList -contains $userName) {
                        Write-Host "Deleting folder $userName on PC: $env:COMPUTERNAME..." -ForegroundColor Yellow
                        try {
                            Remove-Item -Path $folder.FullName -Recurse -Force
                            Write-Host "Folder $userName deleted on PC: $env:COMPUTERNAME..." -ForegroundColor Green
                        } catch {
                            Write-Host "Failed to delete folder $userName on PC: $env:COMPUTERNAME: $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "Folder $userName does not correspond to a disabled user." -ForegroundColor Gray
                    }
                }
            } -ArgumentList $disabledUsers
        } catch {
            Write-Host "Error executing script on PC ${activeComputer}: $_" -ForegroundColor Red
        }
    }
}
