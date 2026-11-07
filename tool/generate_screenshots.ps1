# Regenerates the App Store screenshots into screenshots/ (1290x2796).
# Uses DemoData and fake RevenueCat / Supabase; no real service is contacted.
Set-Location (Split-Path $PSScriptRoot -Parent)
flutter test test/screenshots --dart-define=SCREENSHOTS=true
exit $LASTEXITCODE
