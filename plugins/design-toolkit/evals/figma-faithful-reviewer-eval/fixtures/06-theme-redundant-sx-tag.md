```diff
diff --git a/apps/console/src/features/members/MemberStatusTag.tsx b/apps/console/src/features/members/MemberStatusTag.tsx
new file mode 100644
index 0000000..a81f3c4
--- /dev/null
+++ b/apps/console/src/features/members/MemberStatusTag.tsx
@@ -0,0 +1,23 @@
+import { Tag } from '@acme/acme-ui';
+
+import type { MemberStatus } from '../../api/members';
+
+const TONE: Record<MemberStatus, 'positive' | 'caution' | 'neutral'> = {
+  active: 'positive',
+  invited: 'caution',
+  suspended: 'neutral',
+};
+
+const LABEL: Record<MemberStatus, string> = {
+  active: 'Active',
+  invited: 'Invited',
+  suspended: 'Suspended',
+};
+
+export function MemberStatusTag({ status }: { status: MemberStatus }) {
+  return (
+    <Tag tone={TONE[status]} sx={{ textTransform: 'uppercase', paddingInline: 2 }}>
+      {LABEL[status]}
+    </Tag>
+  );
+}
```
