#!/usr/bin/env bash
set -e

TARGET="${1:?Usage: make.sh <target-name>}"

if make -n "${TARGET}" &>/dev/null; then
  echo "Running 'make ${TARGET}'..."
  make "${TARGET}"
else
  echo "Target '${TARGET}' not found in Makefile, skipping..."
fi
