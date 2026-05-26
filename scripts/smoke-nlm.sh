#!/usr/bin/env sh
set -eu

echo "Checking local nlm installation and auth state."
nlm doctor

echo "Listing notebooks through nlm."
nlm notebook list --json
