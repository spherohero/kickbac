#!/usr/bin/env bash
set -euo pipefail

task_repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
task_package_root="$(mktemp -d "${TMPDIR:-/tmp}/kickbac-auth-check.XXXXXX")"
trap 'rm -r "$task_package_root"' EXIT
mkdir -p "$task_package_root/Sources/Checks"
cp "$task_repo_root/ios/KickBAC/AuthConfiguration.swift" "$task_package_root/Sources/Checks/"
cp "$task_repo_root/ios/KickBAC/AuthSession.swift" "$task_package_root/Sources/Checks/"
cp "$task_repo_root/ios/KickBAC/KickBACAPI.swift" "$task_package_root/Sources/Checks/"
cp "$task_repo_root/ios/KickBAC/DeviceModels.swift" "$task_package_root/Sources/Checks/"
cp "$task_repo_root/ios/KickBAC/BACReading.swift" "$task_package_root/Sources/Checks/"
cp "$task_repo_root/ios/checks/AuthIntegrationChecks.swift" "$task_package_root/Sources/Checks/"
cat > "$task_package_root/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "KickBACAuthChecks",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/auth0/Auth0.swift", exact: "3.1.0")],
    targets: [.executableTarget(name: "Checks", dependencies: [.product(name: "Auth0", package: "Auth0.swift")])],
    swiftLanguageModes: [.v5]
)
SWIFT
swift run --package-path "$task_package_root" --scratch-path "${TMPDIR:-/tmp}/kickbac-auth-check-build" Checks
