```diff
diff --git a/apps/console/src/features/members/MemberRow.tsx b/apps/console/src/features/members/MemberRow.tsx
new file mode 100644
index 0000000..e03c6b8
--- /dev/null
+++ b/apps/console/src/features/members/MemberRow.tsx
@@ -0,0 +1,19 @@
+import { Avatar, Stack, Typography } from '@acme/acme-ui';
+
+import type { Member } from '../../api/members';
+
+export function MemberRow({ member }: { member: Member }) {
+  return (
+    <Stack direction='row' gap={3} sx={{ alignItems: 'center', minInlineSize: 0 }}>
+      <Avatar name={member.name} src={member.avatarUrl} />
+      <Stack gap={0.5} sx={{ minInlineSize: 0 }}>
+        <Typography variant='bodyStrong' ellipsis>
+          {member.name}
+        </Typography>
+        <Typography variant='helper' ellipsis sx={{ color: 'text.secondary', whiteSpace: 'pre-line' }}>
+          {member.note}
+        </Typography>
+      </Stack>
+    </Stack>
+  );
+}
```
