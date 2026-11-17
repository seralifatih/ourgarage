# Runs the two steps that need the RevenueCat secret key:
#   1. tool/create_review_household.py --codes 0
#      (lifetime promo for the App Review demo owner; demo household premium)
#   2. supabase/tests/e2e_claim_premium.py
#
# Holds no secrets. The key is typed at a hidden prompt, every credential lives
# only in this process's environment, nothing is printed, and all of it is
# removed at the end, even on failure.
#
# Run from anywhere (Windows PowerShell 5.1 or later):
#   powershell -ExecutionPolicy Bypass -File tool\run_with_rc_key.ps1

$ErrorActionPreference = 'Stop'
$ProjectRef = 'bqctkdfklzfwoeuortza'
$EnvNames = @(
    'SUPABASE_URL',
    'SUPABASE_ANON_KEY',
    'SUPABASE_SERVICE_ROLE_KEY',
    'REVENUECAT_SECRET_KEY'
)

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Failures = @()

Push-Location $RepoRoot
try {
    # 1. Supabase URL and anon key from dart_defines.json (gitignored).
    $defines = Get-Content -Raw -Path (Join-Path $RepoRoot 'dart_defines.json') | ConvertFrom-Json
    $env:SUPABASE_URL = $defines.SUPABASE_URL
    $env:SUPABASE_ANON_KEY = $defines.SUPABASE_ANON_KEY
    if (-not $env:SUPABASE_URL -or -not $env:SUPABASE_ANON_KEY) {
        throw 'dart_defines.json has no SUPABASE_URL or SUPABASE_ANON_KEY.'
    }

    # Service role key from the Supabase CLI, as the e2e tests do. Parsed in
    # memory, never echoed.
    $keysJson = supabase projects api-keys --project-ref $ProjectRef -o json
    if ($LASTEXITCODE -ne 0) {
        throw 'supabase projects api-keys failed. Is the CLI logged in to the right account?'
    }
    $serviceKey = ($keysJson | Out-String | ConvertFrom-Json) |
        Where-Object { $_.name -eq 'service_role' } |
        Select-Object -First 1 -ExpandProperty api_key
    $keysJson = $null
    if (-not $serviceKey) { throw 'No service_role key in the CLI output.' }
    $env:SUPABASE_SERVICE_ROLE_KEY = $serviceKey
    $serviceKey = $null

    # 2. RevenueCat secret key at a hidden prompt.
    $secure = Read-Host -AsSecureString -Prompt 'RevenueCat secret key (sk_...)'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $env:REVENUECAT_SECRET_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $secure.Dispose()
    }
    if (-not $env:REVENUECAT_SECRET_KEY) { throw 'No RevenueCat key entered.' }
    if (-not $env:REVENUECAT_SECRET_KEY.StartsWith('sk_')) {
        throw 'That is not a RevenueCat secret key (they start with sk_).'
    }

    # 3. Both steps run even if the first fails; each one's result is reported.
    Write-Host ''
    Write-Host '== Demo household: lifetime promo + premium =='
    python -I tool/create_review_household.py --live --codes 0
    if ($LASTEXITCODE -ne 0) { $Failures += "create_review_household.py (exit $LASTEXITCODE)" }

    Write-Host ''
    Write-Host '== e2e_claim_premium.py =='
    python -I supabase/tests/e2e_claim_premium.py --live
    if ($LASTEXITCODE -ne 0) { $Failures += "e2e_claim_premium.py (exit $LASTEXITCODE)" }
}
catch {
    $Failures += "setup: $($_.Exception.Message)"
}
finally {
    # 4. Always remove every credential from the environment.
    foreach ($name in $EnvNames) {
        Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
    }
    Pop-Location
}

Write-Host ''
if ($Failures.Count -eq 0) {
    Write-Host 'All done. Both steps succeeded; credentials removed from the environment.'
    exit 0
}
Write-Host 'Failed:'
$Failures | ForEach-Object { Write-Host "  - $_" }
Write-Host 'Credentials removed from the environment.'
exit 1
