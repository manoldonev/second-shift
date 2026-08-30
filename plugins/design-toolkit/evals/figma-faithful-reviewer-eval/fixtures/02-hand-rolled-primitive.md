```diff
diff --git a/apps/console/src/features/members/InviteMemberForm.tsx b/apps/console/src/features/members/InviteMemberForm.tsx
new file mode 100644
index 0000000..c41a8e9
--- /dev/null
+++ b/apps/console/src/features/members/InviteMemberForm.tsx
@@ -0,0 +1,74 @@
+import { useState } from 'react';
+import { Card, Stack, Typography } from '@acme/acme-ui';
+
+import { useInviteMember } from '../../hooks/useInviteMember';
+
+const ROLES = ['viewer', 'editor', 'owner'] as const;
+
+export function InviteMemberForm({ workspaceId }: { workspaceId: string }) {
+  const [email, setEmail] = useState('');
+  const [role, setRole] = useState<(typeof ROLES)[number]>('viewer');
+  const { mutate, isPending } = useInviteMember(workspaceId);
+
+  return (
+    <Card elevation={0}>
+      <Stack gap={6} sx={{ padding: 6 }}>
+        <Typography variant='sectionTitle'>Invite a teammate</Typography>
+
+        <Stack gap={2}>
+          <Typography variant='fieldLabel'>Email address</Typography>
+          <input
+            type='email'
+            value={email}
+            onChange={(e) => setEmail(e.target.value)}
+            placeholder='name@company.com'
+            style={{
+              blockSize: '2.5rem',
+              paddingInline: '0.75rem',
+              borderRadius: 6,
+              border: '1px solid',
+              borderColor: 'var(--acme-border-default)',
+            }}
+          />
+          <Typography variant='helper'>They will receive an email invitation.</Typography>
+        </Stack>
+
+        <Stack gap={2}>
+          <Typography variant='fieldLabel'>Role</Typography>
+          <select
+            value={role}
+            onChange={(e) => setRole(e.target.value as (typeof ROLES)[number])}
+            style={{ blockSize: '2.5rem' }}
+          >
+            {ROLES.map((r) => (
+              <option key={r} value={r}>
+                {r}
+              </option>
+            ))}
+          </select>
+        </Stack>
+
+        <Stack direction='row' gap={3} sx={{ justifyContent: 'flex-end' }}>
+          <button type='button' onClick={() => setEmail('')}>
+            Clear
+          </button>
+          <button
+            type='submit'
+            disabled={isPending}
+            onClick={() => mutate({ email, role })}
+          >
+            Send invite
+          </button>
+        </Stack>
+      </Stack>
+    </Card>
+  );
+}
```
