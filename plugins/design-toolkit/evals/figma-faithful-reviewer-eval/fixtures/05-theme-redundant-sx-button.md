```diff
diff --git a/apps/console/src/features/members/MembersToolbar.tsx b/apps/console/src/features/members/MembersToolbar.tsx
new file mode 100644
index 0000000..5c1e0a2
--- /dev/null
+++ b/apps/console/src/features/members/MembersToolbar.tsx
@@ -0,0 +1,25 @@
+import { Button, Stack, Typography } from '@acme/acme-ui';
+
+export function MembersToolbar({
+  memberCount,
+  onInvite,
+  onExport,
+}: {
+  memberCount: number;
+  onInvite: () => void;
+  onExport: () => void;
+}) {
+  return (
+    <Stack direction='row' gap={3} sx={{ alignItems: 'center', justifyContent: 'space-between' }}>
+      <Typography variant='sectionTitle'>Members ({memberCount})</Typography>
+      <Stack direction='row' gap={2}>
+        <Button variant='secondary' onClick={onExport} sx={{ textTransform: 'none' }}>
+          Export CSV
+        </Button>
+        <Button variant='primary' onClick={onInvite} sx={{ textTransform: 'none' }}>
+          Invite member
+        </Button>
+      </Stack>
+    </Stack>
+  );
+}
```
