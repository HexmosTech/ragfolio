<#
.SYNOPSIS
    Windows one-line developer toolchain installer.

.DESCRIPTION
    Installs Python 3.12.10 + uv, Git, nvm-windows, Node.js 22.22.0,
    and generates an RSA 4096-bit SSH key pair.

.PARAMETER Email
    Email address used to label the SSH key. If omitted, the script prompts interactively.

.EXAMPLE
    iex (iwr 'https://<host>/install.ps1').Content
    iex (iwr 'https://<host>/install.ps1').Content -Email user@example.com
#>

param(
    [string]$Email = ""
)

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param(
        [int]$n,
        [string]$msg
    )
    Write-Host "[Step $n] $msg"
}

function Write-Ok {
    param([string]$msg)
    Write-Host "[OK] $msg"
}

function Write-Skip {
    param(
        [string]$tool,
        [string]$reason
    )
    Write-Host "[SKIP] $tool - $reason"
}

function Write-Warn {
    param([string]$msg)
    Write-Host "[WARN] $msg"
}

function Write-Fatal {
    param([string]$msg)
    Write-Host "[ERROR] $msg"
    exit 1
}

# ---------------------------------------------------------------------------
# OS guard — Windows only
# ---------------------------------------------------------------------------

$_isWindows = $false
try {
    $_isWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
} catch {
    # Fallback for PowerShell 5.1 where RuntimeInformation may not be available
    $_isWindows = ($env:OS -eq 'Windows_NT')
}

if (-not $_isWindows) {
    Write-Fatal "This script supports Windows only. Detected a non-Windows operating system."
}

# ---------------------------------------------------------------------------
# Email validation and sanitization
# ---------------------------------------------------------------------------

function Test-EmailAddress {
    param([string]$addr)
    return ($addr -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')
}

function Get-SanitizedEmail {
    param([string]$addr)
    return ($addr -replace '[<>:"/\\|?*]', '-')
}

# ---------------------------------------------------------------------------
# Main script body
# ---------------------------------------------------------------------------

# $ErrorActionPreference is set to 'Stop' inside each try/catch block so that
# PowerShell terminating errors are caught and handled explicitly.

# --- Email collection (Task 2) ---
if ($Email -eq "") {
    # Interactive mode: prompt until a valid address is entered
    do {
        $Email = Read-Host "Enter your email address which you used for creating github account."
        if (-not (Test-EmailAddress $Email)) {
            Write-Host "[ERROR] Invalid email address. Please try again."
        }
    } while (-not (Test-EmailAddress $Email))
} else {
    # Parameter mode: validate and exit on failure
    if (-not (Test-EmailAddress $Email)) {
        Write-Fatal "Invalid email address: '$Email'"
    }
}

$rawEmail       = $Email
$sanitizedEmail = Get-SanitizedEmail $Email
# ---------------------------------------------------------------------------
# PATH management helper
# ---------------------------------------------------------------------------

function Add-ToPath {
    param([string]$dir)

    # Read the current persistent User-level PATH
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($null -eq $userPath) { $userPath = '' }

    # Split on ';', filter empty entries, compare case-insensitively
    $userEntries = $userPath -split ';' | Where-Object { $_ -ne '' }
    $alreadyInUser = $userEntries | Where-Object { $_.TrimEnd('\') -ieq $dir.TrimEnd('\') }

    if (-not $alreadyInUser) {
        # Append to User-level PATH and persist it
        $newUserPath = ($userEntries + $dir) -join ';'
        [Environment]::SetEnvironmentVariable('PATH', $newUserPath, 'User')
    }

    # Also update the current-session PATH if not already present
    $sessionEntries = $env:PATH -split ';' | Where-Object { $_ -ne '' }
    $alreadyInSession = $sessionEntries | Where-Object { $_.TrimEnd('\') -ieq $dir.TrimEnd('\') }

    if (-not $alreadyInSession) {
        $env:PATH = ($env:PATH.TrimEnd(';') + ';' + $dir)
    }
}
function Install-Curl {
    Write-Step 1 "Installing curl"

    # Detect — skip if already present
    try {
        $curlVersion = & curl.exe --version 2>&1
        if ($LASTEXITCODE -eq 0 -and $curlVersion -match 'curl ') {
            Write-Skip "curl" "already installed"
            return
        }
    } catch {
        # curl not found — proceed with install
    }

    # Install curl using winget (first-party package source on modern Windows)
    try {
        $ErrorActionPreference = 'Stop'
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Fatal "curl is missing and winget is unavailable. Install curl manually, then rerun."
        }

        Write-Host "Installing curl via winget..."
        & winget install --id cURL.cURL --exact --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget install cURL.cURL exited with code $LASTEXITCODE"
        }

        Write-Ok "curl installed"
    } catch {
        Write-Fatal "curl installation failed: $_"
    }
}
function Install-Python {
    Write-Step 2 "Installing Python 3.12.10 + uv"

    # Detect — skip if already present
    try {
        $pyVersion = & python --version 2>&1
        if ($pyVersion -match '3\.12\.10') {
            Write-Skip "Python" "3.12.10 already installed"
            # Still ensure PATH is up to date
            Add-ToPath "$env:LOCALAPPDATA\Programs\Python\Python312"
            return
        }
    } catch {
        # python not found — proceed with install
    }

    # Download and install
    $installer = "$env:TEMP\python-3.12.10-amd64.exe"
    $url       = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe"

    try {
        $ErrorActionPreference = 'Stop'
        Write-Host "Downloading Python 3.12.10..."
        & curl.exe -L --fail --output $installer $url
        if ($LASTEXITCODE -ne 0) {
            throw "curl download failed with code $LASTEXITCODE"
        }

        Write-Host "Running Python installer silently..."
        $proc = Start-Process -FilePath $installer `
            -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Python installer exited with code $($proc.ExitCode)"
        }

        Write-Ok "Python 3.12.10 installed"
    } catch {
        Write-Warn "Python installation failed: $_"
        return
    } finally {
        if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
    }

    # Add Python to PATH for this session and persistently
    Add-ToPath "$env:LOCALAPPDATA\Programs\Python\Python312"

    # Install uv via pip
    try {
        $ErrorActionPreference = 'Stop'
        & pip install uv
        if ($LASTEXITCODE -ne 0) {
            throw "pip install uv exited with code $LASTEXITCODE"
        }
        Write-Ok "uv installed"
    } catch {
        Write-Warn "uv installation failed: $_"
    }
}
function Install-Git {
    Write-Step 3 "Installing Git"

    # Detect — skip if already present
    try {
        $gitVersion = & git --version 2>&1
        if ($gitVersion -match 'git version') {
            Write-Skip "Git" "already installed ($gitVersion)"
            Add-ToPath "C:\Program Files\Git\cmd"
            return
        }
    } catch {
        # git not found — proceed with install
    }

    # Download and install
    $installer = "$env:TEMP\Git-2.47.1-64-bit.exe"
    $url       = "https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe"

    try {
        $ErrorActionPreference = 'Stop'
        Write-Host "Downloading Git for Windows..."
        & curl.exe -L --fail --output $installer $url
        if ($LASTEXITCODE -ne 0) {
            throw "curl download failed with code $LASTEXITCODE"
        }

        Write-Host "Running Git installer silently..."
        $proc = Start-Process -FilePath $installer `
            -ArgumentList "/VERYSILENT /NORESTART" `
            -Wait -PassThru
        if ($proc.ExitCode -ne 0) {
            throw "Git installer exited with code $($proc.ExitCode)"
        }

        Write-Ok "Git installed"
    } catch {
        Write-Warn "Git installation failed: $_"
        return
    } finally {
        if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
    }

    # Add Git to PATH for this session and persistently
    Add-ToPath "C:\Program Files\Git\cmd"
}
function Install-NvmAndNode {
    Write-Step 4 "Installing nvm-windows and Node.js 22.22.0"

    # Detect nvm — skip if already present
    $nvmPresent = $false
    try {
        $nvmVersion = & nvm version 2>&1
        if ($LASTEXITCODE -eq 0 -and $nvmVersion -ne '') {
            Write-Skip "nvm-windows" "already installed ($nvmVersion)"
            $nvmPresent = $true
        }
    } catch {
        # nvm not found — proceed with install
    }

    if (-not $nvmPresent) {
        $installer = "$env:TEMP\nvm-setup.exe"
        $url       = "https://github.com/coreybutler/nvm-windows/releases/download/1.1.12/nvm-setup.exe"

        try {
            $ErrorActionPreference = 'Stop'
            Write-Host "Downloading nvm-setup.exe..."
            & curl.exe -L --fail --output $installer $url
            if ($LASTEXITCODE -ne 0) {
                throw "curl download failed with code $LASTEXITCODE"
            }

            Write-Host "Running nvm installer silently..."
            $proc = Start-Process -FilePath $installer `
                -ArgumentList "/S" `
                -Wait -PassThru
            if ($proc.ExitCode -ne 0) {
                throw "nvm installer exited with code $($proc.ExitCode)"
            }

            Write-Ok "nvm-windows installed"
        } catch {
            Write-Warn "nvm-windows installation failed: $_"
            return
        } finally {
            if (Test-Path $installer) { Remove-Item $installer -Force -ErrorAction SilentlyContinue }
        }

        # Add nvm to current session PATH so subsequent commands can find it
        Add-ToPath "$env:APPDATA\nvm"
    }

    # Detect Node.js 22.22.0 — skip if already the active version
    $nodePresent = $false
    try {
        $nvmList = & nvm list 2>&1
        if ($nvmList -match '\*\s*22\.22\.0') {
            Write-Skip "Node.js" "22.22.0 already active"
            $nodePresent = $true
        }
    } catch {
        # nvm list failed — proceed with install
    }

    if (-not $nodePresent) {
        try {
            $ErrorActionPreference = 'Stop'
            Write-Host "Installing Node.js 22.22.0 via nvm..."
            & nvm install 22.22.0
            if ($LASTEXITCODE -ne 0) {
                throw "nvm install 22.22.0 exited with code $LASTEXITCODE"
            }

            & nvm use 22.22.0
            if ($LASTEXITCODE -ne 0) {
                throw "nvm use 22.22.0 exited with code $LASTEXITCODE"
            }

            Write-Ok "Node.js 22.22.0 installed and active"
        } catch {
            Write-Warn "Node.js installation failed: $_"
            return
        }
    }

    # Add nvm and Node.js binary directories to PATH
    # nvm-windows uses a symlink at C:\Program Files\nodejs (set during nvm install)
    # that points to the active Node version; add both nvm home and the symlink path.
    Add-ToPath "$env:APPDATA\nvm"
    Add-ToPath "C:\Program Files\nodejs"
}
function New-SshKeyPair {
    param(
        [string]$email,
        [string]$sanitizedEmail
    )

    Write-Step 5 "Generating SSH key pair"

    $sshDir      = Join-Path $HOME ".ssh"
    $privateKey  = Join-Path $sshDir "id-rsa-$sanitizedEmail"
    $publicKey   = "$privateKey.pub"

    # Ensure ~/.ssh exists (Requirement 7.3)
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    # Check if ssh-keygen is available (Requirement 7.6)
    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        Write-Fatal "ssh-keygen is not available on PATH. Please install OpenSSH and try again."
    }

    # Skip generation if key already exists (Requirement 7.4)
    if (Test-Path $privateKey) {
        Write-Skip "SSH key" "key file already exists at $privateKey"
    } else {
        # Generate RSA 4096-bit key pair with no passphrase (Requirements 7.1, 7.2)
        $keygenArgs = @('-t', 'rsa', '-b', '4096', '-C', $email, '-f', $privateKey, '-N', '""')
        & ssh-keygen @keygenArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Fatal "ssh-keygen failed with exit code $LASTEXITCODE"
        }
        Write-Ok "SSH key pair generated at $privateKey"
    }

    # Configure SSH agent service
    try {
        $ErrorActionPreference = 'Stop'
        Write-Host "Configuring SSH agent service..."
        
        # Set SSH agent to start automatically
        $sshAgent = Get-Service ssh-agent -ErrorAction SilentlyContinue
        if ($sshAgent) {
            Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
            
            # Start the service if not already running
            if ($sshAgent.Status -ne 'Running') {
                Start-Service ssh-agent -ErrorAction SilentlyContinue
            }
            
            # Add key to agent
            & ssh-add $privateKey 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "SSH key added to agent"
            }
        }
    } catch {
        Write-Warn "Could not configure SSH agent: $_"
    }

    # Create SSH config file for GitHub
    try {
        $ErrorActionPreference = 'Stop'
        $sshConfigPath = Join-Path $sshDir "config"
        
        $sshConfig = @"
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id-rsa-$sanitizedEmail
    IdentitiesOnly yes
"@

        # Only create if it doesn't exist or doesn't have GitHub entry
        if (-not (Test-Path $sshConfigPath)) {
            Set-Content -Path $sshConfigPath -Value $sshConfig -Force
            Write-Ok "SSH config file created at $sshConfigPath"
        } else {
            $existingConfig = Get-Content $sshConfigPath -Raw
            if ($existingConfig -notmatch 'Host github.com') {
                Add-Content -Path $sshConfigPath -Value ("`n" + $sshConfig)
                Write-Ok "GitHub entry added to SSH config"
            } else {
                Write-Skip "SSH config" "GitHub entry already exists"
            }
        }
    } catch {
        Write-Warn "Could not create SSH config: $_"
    }

    # Display public key content (Requirement 7.5)
    Write-Host ""
    Write-Host "Your public SSH key ($publicKey):"
    Write-Host (Get-Content $publicKey -Raw)
}
# ---------------------------------------------------------------------------
# Main installation pipeline
# ---------------------------------------------------------------------------

Install-Curl
Install-Python
Install-Git
Install-NvmAndNode
New-SshKeyPair -email $rawEmail -sanitizedEmail $sanitizedEmail

Write-Host ""
Write-Ok "All steps completed successfully."
exit 0
