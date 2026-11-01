#!/bin/zsh
# Builds and runs the package tests with swiftc + a tiny XCTest stand-in.
# Use this when only the Command Line Tools are installed; with Xcode, run the tests from Xcode instead.
set -euo pipefail
cd "${0:A:h}/.."
B=.build/manual-tests
rm -rf $B && mkdir -p $B
T=(-target arm64-apple-macos13 -parse-as-library -enable-testing)

swiftc $T -emit-library -emit-module -module-name XCTest scripts/xctest-shim/XCTest.swift \
  -o $B/libXCTest.dylib -emit-module-path $B/XCTest.swiftmodule -Xlinker -install_name -Xlinker @rpath/libXCTest.dylib
swiftc $T -emit-library -emit-module -module-name DetectorCore Sources/DetectorCore/*.swift \
  -o $B/libDetectorCore.dylib -emit-module-path $B/DetectorCore.swiftmodule -Xlinker -install_name -Xlinker @rpath/libDetectorCore.dylib
swiftc $T -emit-library -emit-module -module-name MarketData Sources/MarketData/*.swift -I $B -L $B -lDetectorCore \
  -o $B/libMarketData.dylib -emit-module-path $B/MarketData.swiftmodule -Xlinker -install_name -Xlinker @rpath/libMarketData.dylib

cat > $B/main.swift <<'EOF'
import XCTest
var total = 0, failed = 0
func add(_ r: (Int, Int)) { total += r.0; failed += r.1 }
add(await runShimTests(DetectorEngineTests.self, DetectorEngineTests.allTests))
add(await runShimTests(AlertDeduplicatorTests.self, AlertDeduplicatorTests.allTests))
add(await runShimTests(MarketCalendarTests.self, MarketCalendarTests.allTests))
add(await runShimTests(SettingsAndFormatterTests.self, SettingsAndFormatterTests.allTests))
add(await runShimTests(MonitorRunnerTests.self, MonitorRunnerTests.allTests))
print("\n\(total - failed)/\(total) tests passed")
exit(failed == 0 ? 0 : 1)
EOF
swiftc -target arm64-apple-macos13 -module-name DetectorCoreTests Tests/DetectorCoreTests/*.swift $B/main.swift \
  -I $B -L $B -lXCTest -lDetectorCore -lMarketData -Xlinker -rpath -Xlinker @executable_path -o $B/run-tests
$B/run-tests
