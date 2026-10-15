```diff
diff --git a/apps/console/src/features/members/RemoveMemberDialog.tsx b/apps/console/src/features/members/RemoveMemberDialog.tsx
new file mode 100644
index 0000000..d4e9b70
--- /dev/null
+++ b/apps/console/src/features/members/RemoveMemberDialog.tsx
@@ -0,0 +1,33 @@
+import { Button, Dialog, Stack, Typography } from '@acme/acme-ui';
+
+export function RemoveMemberDialog({
+  open,
+  memberName,
+  onCancel,
+  onConfirm,
+}: {
+  open: boolean;
+  memberName: string;
+  onCancel: () => void;
+  onConfirm: () => void;
+}) {
+  return (
+    <Dialog open={open} onClose={onCancel} title='Remove member'>
+      <Stack gap={6}>
+        <Typography variant='body'>
+          {memberName} loses access to this workspace immediately.
+        </Typography>
+        <Stack direction='row' gap={2} sx={{ justifyContent: 'flex-end' }}>
+          <Button variant='secondary' onClick={onCancel}>
+            Cancel
+          </Button>
+          {/* acme-ui's Button lets a long label wrap onto a second line, which breaks the
+              footer's alignment — pin the label to one line. */}
+          <Button variant='primary' onClick={onConfirm} sx={{ whiteSpace: 'nowrap' }}>
+            Remove {memberName}
+          </Button>
+        </Stack>
+      </Stack>
+    </Dialog>
+  );
+}
```
