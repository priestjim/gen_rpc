#!/usr/bin/env bash
#
# Prepares the working tree for a release of gen_rpc:
#
#   - Turns the "Unreleased" section of CHANGELOG.md into the section of VERSION
#     and adds a new, empty "Unreleased" section above it
#   - Sets the version in src/gen_rpc.app.src and mix.exs
#   - Writes the release notes (the entries of the released section) to NOTES_FILE
#
# Usage: prepare-release.sh VERSION NOTES_FILE
#
# It only edits files, committing, tagging and publishing is up to the caller.

set -euo pipefail

VERSION="${1:-}"
NOTES_FILE="${2:-}"

if [[ -z "$VERSION" || -z "$NOTES_FILE" ]]; then
    echo "Usage: $0 VERSION NOTES_FILE" >&2
    exit 2
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid version \"$VERSION\", expected MAJOR.MINOR.PATCH[-PRERELEASE]" >&2
    exit 1
fi

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if grep -q "^## ${VERSION//./\\.}\$" CHANGELOG.md; then
    echo "CHANGELOG.md already has a section for $VERSION" >&2
    exit 1
fi

if [[ $(grep -c '^## Unreleased$' CHANGELOG.md) -ne 1 ]]; then
    echo "CHANGELOG.md must contain exactly one \"## Unreleased\" section" >&2
    exit 1
fi

# The release notes are everything between "## Unreleased" and the next section
awk '
    /^## Unreleased$/ { found = 1; next }
    found && /^## /   { exit }
    found             { print }
' CHANGELOG.md | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | sed -e '/./,$!d' > "$NOTES_FILE"

if ! grep -q '[^[:space:]]' "$NOTES_FILE"; then
    echo "The Unreleased section of CHANGELOG.md has no entries, nothing to release" >&2
    exit 1
fi

# Promote Unreleased to the new version and open a fresh, empty Unreleased
awk -v version="$VERSION" '
    /^## Unreleased$/ && !done { print "## Unreleased\n\n## " version; done = 1; next }
    { print }
' CHANGELOG.md > CHANGELOG.md.new
mv CHANGELOG.md.new CHANGELOG.md

# Version in the application resource file, whatever it was before ("git" or a string)
sed -E "s/^([[:space:]]*\\{vsn,[[:space:]]*)[^}]*\\}/\\1\"${VERSION}\"}/" src/gen_rpc.app.src > src/gen_rpc.app.src.new
mv src/gen_rpc.app.src.new src/gen_rpc.app.src

sed -E "s/^([[:space:]]*@version[[:space:]]+)\"[^\"]*\"/\\1\"${VERSION}\"/" mix.exs > mix.exs.new
mv mix.exs.new mix.exs

grep -q "{vsn, \"${VERSION}\"}" src/gen_rpc.app.src || { echo "Failed to update src/gen_rpc.app.src" >&2; exit 1; }
grep -q "@version \"${VERSION}\"" mix.exs || { echo "Failed to update mix.exs" >&2; exit 1; }

echo "Prepared release $VERSION"
