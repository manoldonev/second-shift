```diff
diff --git a/apps/console/src/features/members/RoleMenu.tsx b/apps/console/src/features/members/RoleMenu.tsx
new file mode 100644
index 0000000..7b20e5f
--- /dev/null
+++ b/apps/console/src/features/members/RoleMenu.tsx
@@ -0,0 +1,37 @@
+import { useState } from 'react';
+
+import { Button, Menu, Stack } from '@acme/acme-ui';
+
+import type { MemberRole } from '../../api/members';
+
+const ROLES: MemberRole[] = ['owner', 'admin', 'member', 'viewer'];
+
+export function RoleMenu({ role, onChange }: { role: MemberRole; onChange: (next: MemberRole) => void }) {
+  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
+
+  return (
+    <>
+      <Button variant='quiet' onClick={(event) => setAnchor(event.currentTarget)}>
+        {role}
+      </Button>
+      {/* acme-ui's Menu renders its paper at zIndex 1, so it opens underneath the sticky
+          members table header. Raise it above the app's fixed layers. */}
+      <Menu open={anchor !== null} anchorEl={anchor} onClose={() => setAnchor(null)} sx={{ zIndex: 1300 }}>
+        <Stack gap={1}>
+          {ROLES.map((next) => (
+            <Button
+              key={next}
+              variant='quiet'
+              onClick={() => {
+                onChange(next);
+                setAnchor(null);
+              }}
+            >
+              {next}
+            </Button>
+          ))}
+        </Stack>
+      </Menu>
+    </>
+  );
+}
```
