function Exe-StartCommands {
    $ErrorActionPreference = "Stop"
    $cred = Get-Credential

    $regions = @(
        "OU=Computers,OU=Mango,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-che,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departments,OU=Mango-ekb,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-kln,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-krsnd,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departaments,OU=Mango-kzn,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departaments,OU=Mango-nnv,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-nsk,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-prm,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departaments,OU=Mango-rnd,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departaments,OU=Mango-sam,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Departmens,OU=Mango-spb,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-Ufa,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-vld,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-vlg,DC=corp,DC=mango,DC=ru",
        "OU=Computers,OU=Mango-vrn,DC=corp,DC=mango,DC=ru"
    )

    # Нумерация и шахматная раскраска регионов
    Write-Host "Выберите регионы для обработки:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $regions.Count; $i++) {
        $color = if ($i % 2 -eq 0) { 'White' } else { 'Gray' }
        Write-Host "$($i + 1). $($regions[$i])" -ForegroundColor $color
    }

    # Ввод пользователя
    $selectedRegions = Read-Host "Введите номера регионов через запятую (например, 1,3,7), или 'all' для выбора всех"
    
    # Если выбраны все регионы
    if ($selectedRegions -eq "all") {
        $selectedRegions = 1..$regions.Count
    } else {
        # Преобразуем ввод в массив чисел
        $selectedRegions = $selectedRegions -split ',' | ForEach-Object { [int]$_ }
    }

    $selectedRegions = $selectedRegions | Where-Object { $_ -ge 1 -and $_ -le $regions.Count }

    Write-Host "Выбрано регионов: $($selectedRegions.Count)" -ForegroundColor Green

    $disabledUsers = @()
    $disabledUserDetails = @()
    $disabledUserLogins = @()
    $activeComputersPool = @()
    $totalOnline = 0
    $totalOffline = 0

    if (-not (Check-InstallModule -moduleName "ActiveDirectory")) {
        Write-Host "Модуль ActiveDirectory не установлен. Скрипт не может продолжить выполнение." -ForegroundColor Red
        return
    }

    Write-Host "Получение списка отключенных учетных записей..." -ForegroundColor Yellow
    try {
        # Получение полной информации об отключенных пользователях
        $disabledUsers = Get-ADUser -Filter {Enabled -eq $false -and DisplayName -like "*уволен*"} -Properties SamAccountName, DisplayName, LastLogonDate |
                         Select-Object SamAccountName, DisplayName, LastLogonDate

        # Логины пользователей в нижнем регистре
        $disabledUserLogins = $disabledUsers | Select-Object -ExpandProperty SamAccountName | ForEach-Object { $_.ToLower() }
        $disabledUserDetails = $disabledUsers

        Write-Host "Найдено отключенных пользователей: $($disabledUsers.Count)" -ForegroundColor Green
        Write-Host "Список пользователей:" -ForegroundColor Cyan
        foreach ($user in $disabledUsers) {
            Write-Host " - Логин: $($user.SamAccountName), Имя: $($user.DisplayName), Последний вход: $($user.LastLogonDate)" -ForegroundColor White
        }
    } catch {
        Write-Host "Ошибка получения отключенных пользователей: $_" -ForegroundColor Red
        return
    }

    # Запрос на выбор массового или точечного удаления
    $deleteChoice = Read-Host "Выберите вариант удаления: (1) Массовое удаление, (2) Точечное удаление"

    foreach ($regionIndex in $selectedRegions) {
        $region = $regions[$regionIndex - 1]
        Write-Host "Поиск компьютеров в регионе: $region" -ForegroundColor Yellow

        try {
            $computers = Get-ADComputer -Filter * -SearchBase $region | Select-Object -ExpandProperty Name

            if ($computers.Count -eq 0) {
                Write-Host "Не найдено компьютеров в регионе ${region}." -ForegroundColor Red
                continue
            }

            Write-Host "Найдено компьютеров в регионе ${region}: $($computers.Count)" -ForegroundColor Green

            foreach ($computer in $computers) {
                $isOnline = Test-Connection -ComputerName $computer -Count 1 -Quiet
                if ($isOnline) {
                    Write-Host "Компьютер $computer доступен." -ForegroundColor Green
                    $activeComputersPool += $computer
                    $totalOnline++
                } else {
                    Write-Host "Компьютер $computer недоступен." -ForegroundColor Red
                    $totalOffline++
                }
            }
        } catch {
            Write-Host "Ошибка при обработке региона ${region}: $_" -ForegroundColor Red
        }
    }

    Write-Host "Количество активных ПК: $totalOnline" -ForegroundColor Cyan
    Write-Host "Количество неактивных ПК: $totalOffline" -ForegroundColor Cyan

    foreach ($activeComputer in $activeComputersPool) {
        try {
            Write-Host "Проверка и удаление папок пользователей на ПК: $activeComputer..." -ForegroundColor Yellow

            Invoke-Command -ComputerName $activeComputer -Credential $cred -ScriptBlock {
                param ($disabledUsersList, $disabledUsersDetails, $deleteChoice)

                $userFoldersPath = "C:\Users"
                Write-Host "Сканирование папок в $userFoldersPath на ПК: $env:COMPUTERNAME..." -ForegroundColor Cyan
                $folders = Get-ChildItem -Path $userFoldersPath -Directory

                $foldersToDelete = @()

                foreach ($folder in $folders) {
                    $folderName = $folder.Name.ToLower()
                    Write-Host "Обнаружена папка $folderName на ПК: $env:COMPUTERNAME." -ForegroundColor Yellow

                    # Проверяем, есть ли совпадение с логинами отключенных пользователей
                    $matchingUser = $disabledUsersDetails | Where-Object { $_.SamAccountName -ieq $folderName }

                    if ($matchingUser) {
                        $userDisplayName = $matchingUser.DisplayName
                        $lastLogonDate = $matchingUser.LastLogonDate

                        # Проверка, что прошло больше 30 дней с последнего входа
                        $dateDiff = (Get-Date) - $lastLogonDate
                        if ($dateDiff.Days -gt 30) {
                            Write-Host "Папка $folderName соответствует отключенному пользователю ($userDisplayName, Последний вход: $lastLogonDate)."

                            # Добавляем папку в список для удаления
                            $foldersToDelete += $folder
                        } else {
                            Write-Host "Последний вход в систему для $folderName был менее 30 дней назад. Пропускаем." -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "Папка $folderName не соответствует отключенным пользователям. Пропускаем." -ForegroundColor Gray
                    }
                }

                # Массовое удаление
                if ($deleteChoice -eq '1') {
                    foreach ($folder in $foldersToDelete) {
                        Write-Host "Попытка удаления папки $($folder.Name) на ПК: $env:COMPUTERNAME..." -ForegroundColor Cyan
                        try {
                            Remove-Item -Path $folder.FullName -Recurse -Force
                            Write-Host "Папка $($folder.Name) успешно удалена на ПК: $env:COMPUTERNAME." -ForegroundColor Green
                        } catch {
                            Write-Host "Не удалось удалить папку $($folder.Name) на ПК: $env:COMPUTERNAME. Ошибка: $_" -ForegroundColor Red
                        }
                    }
                }
                # Точечное удаление
                elseif ($deleteChoice -eq '2') {
                    foreach ($folder in $foldersToDelete) {
                        # Запрос подтверждения для каждой папки
                        $confirmation = Read-Host "Хотите удалить папку $($folder.Name) на ПК $env:COMPUTERNAME? (Y/N)"
                        if ($confirmation -eq 'Y') {
                            Write-Host "Попытка удаления папки $($folder.Name) на ПК: $env:COMPUTERNAME..." -ForegroundColor Cyan
                            try {
                                Remove-Item -Path $folder.FullName -Recurse -Force
                                Write-Host "Папка $($folder.Name) успешно удалена на ПК: $env:COMPUTERNAME." -ForegroundColor Green
                            } catch {
                                Write-Host "Не удалось удалить папку $($folder.Name) на ПК: $env:COMPUTERNAME. Ошибка: $_" -ForegroundColor Red
                            }
                        } else {
                            Write-Host "Папка $($folder.Name) на ПК $env:COMPUTERNAME не удалена." -ForegroundColor Gray
                        }
                    }
                }
            } -ArgumentList $disabledUserLogins, $disabledUserDetails, $deleteChoice
        } catch {
            Write-Host "Ошибка выполнения скрипта на ПК ${activeComputer}: $_" -ForegroundColor Red
        }
    }
}

