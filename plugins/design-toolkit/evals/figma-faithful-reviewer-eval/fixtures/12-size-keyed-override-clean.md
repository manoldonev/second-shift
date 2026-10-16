```diff
diff --git a/apps/console/src/features/members/MembersFilters.tsx b/apps/console/src/features/members/MembersFilters.tsx
new file mode 100644
index 0000000..7a1d2e3
--- /dev/null
+++ b/apps/console/src/features/members/MembersFilters.tsx
@@ -0,0 +1,21 @@
+import { Button, Stack, Typography } from '@acme/acme-ui';
+
+export function MembersFilters({
+  activeCount,
+  onClear,
+}: {
+  activeCount: number;
+  onClear: () => void;
+}) {
+  return (
+    <Stack direction='row' gap={3} sx={{ alignItems: 'center' }}>
+      <Typography variant='fieldLabel'>Filters ({activeCount})</Typography>
+      <Stack direction='row' gap={2}>
+        <Button variant='secondary' onClick={onClear} sx={{ paddingInline: 2 }}>
+          Clear all
+        </Button>
+      </Stack>
+    </Stack>
+  );
+}
```
