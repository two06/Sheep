#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# The command-line-tools toolchain ships Testing as a framework outside the SDK.
frameworks="$(xcode-select -p)/Library/Developer/Frameworks"
if [[ -d "$frameworks/Testing.framework" ]]; then
    swift test --disable-xctest --enable-swift-testing -Xswiftc -F -Xswiftc "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "${frameworks:h}/usr/lib" "$@"
else
    swift test --disable-xctest --enable-swift-testing "$@"
fi
