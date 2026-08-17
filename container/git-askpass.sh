#!/usr/bin/env sh
set -eu

case "${1:-}" in
    *Username*)
        printf '%s\n' x-access-token
        ;;
    *Password*)
        test -n "${GITHUB_PAT:-}" || exit 1
        printf '%s\n' "$GITHUB_PAT"
        ;;
    *)
        exit 1
        ;;
esac
