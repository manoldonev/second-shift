```diff
diff --git a/apps/console/src/features/members/MemberSearch.tsx b/apps/console/src/features/members/MemberSearch.tsx
new file mode 100644
index 0000000..19f6d2a
--- /dev/null
+++ b/apps/console/src/features/members/MemberSearch.tsx
@@ -0,0 +1,14 @@
+import { Stack, TextField } from '@acme/acme-ui';
+
+export function MemberSearch({ query, onQueryChange }: { query: string; onQueryChange: (next: string) => void }) {
+  return (
+    <Stack direction='row' gap={2} sx={{ alignItems: 'center' }}>
+      <TextField
+        aria-label='Search members'
+        placeholder='Name or email'
+        value={query}
+        onChange={onQueryChange}
+      />
+    </Stack>
+  );
+}
```
