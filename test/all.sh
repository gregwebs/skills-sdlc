#!/usr/bin/env bash
set -euo pipefail

./test/check-ci-runs.sh
./test/install-agents.sh
./test/install-standards.sh
./test/install-skills.sh
./test/repository-interface.sh
./test/check-ci-runs.sh
./test/check-verus-cheats.sh
./scripts/check-skill-inlines.sh
./scripts/shellcheck.sh
git diff --check
