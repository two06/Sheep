#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/validation
stamp="$(date +%Y%m%d-%H%M%S)"
for count in 1 10; do
    open -n "$PWD/dist/Sheep.app" --args --soak "$count" --metrics "$PWD/.build/validation/soak-$stamp-$count.jsonl"
done
print "Two independent runs launched (11 sheep total). Each exits after about 31 minutes."
print "Logs: $PWD/.build/validation/soak-$stamp-{1,10}.jsonl"
print "At 10s each pauses; at 20s it hides; at 30s it resumes for at least 30 minutes."
