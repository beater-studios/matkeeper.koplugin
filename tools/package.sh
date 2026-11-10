#!/bin/sh
# Builds the plugin zip in dist/, with its checksum.
set -eu
. "$(dirname "$0")/package_lib.sh"
package_start "matkeeper"
package_stage
package_add assets data/i18n.lua
package_zip
