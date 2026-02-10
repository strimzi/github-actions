#!/usr/bin/env bash
set -e

# We exclude .github and github-actions folders because in tests we copy there actions to test changes more easily
CHANGED_FILES=$(git diff --name-status -- ':!.github' ':!github-actions')
UNTRACKED_FILES=$(git ls-files --other --exclude-standard -- ':!.github' ':!github-actions')

if [ -n "$CHANGED_FILES" ] || [ -n "$UNTRACKED_FILES" ] ; then
    if [ -n "$CHANGED_FILES" ] ; then
        echo "ERROR: Uncommitted changes in tracked files:"
        echo "$CHANGED_FILES"
    fi

    if [ -n "$UNTRACKED_FILES" ] ; then
        echo "ERROR: Untracked files:"
        echo "$UNTRACKED_FILES"
    fi

    echo "Please, make sure you run all steps that are needed to propagate all changes to generated files and then commit the changes before push."
    exit 1
fi
