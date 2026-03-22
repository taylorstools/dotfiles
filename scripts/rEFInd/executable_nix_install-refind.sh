#!/usr/bin/env bash

set -euo pipefail

# Clone rEFInd repo
[ -d ~/rEFInd ] || git clone https://github.com/RefindPlusRepo/rEFInd.git ~/rEFInd

# Apply MR #55
patch_file=~/scripts/rEFInd/refind-duplicate-tools.patch
[ ! -f "$patch_file" ] && cat > "$patch_file" <<'EOF'
diff --git a/refind/main.c b/refind/main.c
index 4b1a2f7..8c3d9a2 100644
--- a/refind/main.c
+++ b/refind/main.c
@@ -1243,7 +1243,9 @@
-    SetMem(Tools, sizeof(Tools), 0);
+    if (Tools != NULL) {
+        SetMem(Tools, sizeof(Tools), 0);
+    }
EOF

git -C ~/rEFInd apply "$patch_file" || true

# Build and install rEFInd
nix-shell ~/scripts/rEFInd/shell.nix --run "sudo refind-install"