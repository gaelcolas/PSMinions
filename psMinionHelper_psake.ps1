#requires -modules Psake
Task default

Properties {
    $myPSmodulePath = "$env:ProgramFiles\WindowsPowerShell\Modules"
    $ModuleFolder = $here | Split-Path -Leaf
}


Task Install-Python { 
    if (-not ($python = (python.exe --version))) 
    {
        Find-Package Python -Source Chocolatey |  install-package -Force
    }
    else
    {
        "Python is already installed: $python"
    }
}

Task Install-Celery {
    if (-not (where.exe python))
    {
        "Python is not installed or not in PATH"
    }
    elseif ( -not (python -m pip list | select-string celery))
    {
        "Installing Celery"
        Python.exe -m pip install celery
    }
    else
    {
        "Celery seems to be installed"
        if (!(where.exe celery))
        {
            $Celery = Join-path (split-path (get-package Python3).Source -Parent) 'tools\scripts' 
            $Env:Path += ";$Celery"
        }
    }
}

Task InstallTelnet {

    if ((Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue))
    {
        Install-WindowsFeature 'telnet-client'
    }
    else {
        pkgmgr /iu:"TelnetClient"
    }
    

}

Task CreatePSModuleSymlink  {
    $targetModulePath = Join-path $myPSmodulePath $ModuleFolder
    $ExistingSymLinkInModulePath = $env:PSModulePath -Split ';' |`
        Get-ChildItem -ErrorAction SilentlyContinue |`
            Where-Object {
                $_.Attributes -match 'ReparsePoint'
            }

    if ($ExistingSymLinkInModulePath.FullName -notcontains $targetModulePath)
    {
        New-Item -ItemType SymbolicLink -Path $targetModulePath -Target $here
    }
    else {
        Write-Warning "$targetModulePath already exists in PSModulePath"
    }
}

Task CreateKitchenSymLink  {
     New-Item -ItemType SymbolicLink -Target ..\RabbitMQ\.kitchen -path .\.kitchen
}