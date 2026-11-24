#!/usr/bin/env bash
# A SANE setup with only the `test` backend (a pretend scanner), for tests:
#   eval "$(scripts/sane-test-env.sh)"
# Prints the exports; the folder lives under $XDG_RUNTIME_DIR or /tmp.
dir="${XDG_RUNTIME_DIR:-/tmp}/sheaf-sane-test"
mkdir -p "$dir"
echo test > "$dir/dll.conf"
# Two pretend scanners; the feeder holds 3 sheets.
cat > "$dir/test.conf" <<'CONF'
number_of_devices 2
CONF
echo "export SANE_CONFIG_DIR=$dir"
