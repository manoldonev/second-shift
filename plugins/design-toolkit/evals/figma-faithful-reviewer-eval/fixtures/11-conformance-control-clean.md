```diff
diff --git a/apps/console/src/features/members/MembersPanel.tsx b/apps/console/src/features/members/MembersPanel.tsx
new file mode 100644
index 0000000..c6a4f19
--- /dev/null
+++ b/apps/console/src/features/members/MembersPanel.tsx
@@ -0,0 +1,65 @@
+import { useState } from 'react';
+
+import { Button, Menu, Stack, Tag, TextField, Typography } from '@acme/acme-ui';
+
+import type { Member, MemberRole } from '../../api/members';
+
+const ROLES: MemberRole[] = ['owner', 'admin', 'member', 'viewer'];
+
+// Eight 40px role rows; a longer list scrolls. Off the spacing scale, so it is named here.
+const ROLE_MENU_MAX_BLOCK_SIZE = '320px';
+
+export function MembersPanel({
+  members,
+  query,
+  onQueryChange,
+  onInvite,
+}: {
+  members: Member[];
+  query: string;
+  onQueryChange: (next: string) => void;
+  onInvite: () => void;
+}) {
+  const [anchor, setAnchor] = useState<HTMLElement | null>(null);
+
+  return (
+    <Stack gap={4}>
+      <Stack direction='row' gap={2} sx={{ alignItems: 'center' }}>
+        <TextField
+          placeholder='Name or email'
+          value={query}
+          onChange={onQueryChange}
+          inputProps={{ 'aria-label': 'Search members' }}
+        />
+        <Button variant='primary' onClick={onInvite} sx={{ flexShrink: 0 }}>
+          Invite member
+        </Button>
+      </Stack>
+      {members.map((member) => (
+        <Stack key={member.id} direction='row' gap={3} sx={{ alignItems: 'center', minInlineSize: 0 }}>
+          <Typography variant='body' ellipsis sx={{ color: 'text.secondary' }}>
+            {member.email}
+          </Typography>
+          <Tag tone={member.active ? 'positive' : 'neutral'}>{member.active ? 'Active' : 'Inactive'}</Tag>
+        </Stack>
+      ))}
+      <Button variant='quiet' onClick={(event) => setAnchor(event.currentTarget)}>
+        Filter by role
+      </Button>
+      {/* acme-ui's Menu sets no maximum height on its paper, so a long role list would run off
+          the screen. Cap it and let the list scroll. */}
+      <Menu
+        open={anchor !== null}
+        anchorEl={anchor}
+        onClose={() => setAnchor(null)}
+        sx={{ maxBlockSize: ROLE_MENU_MAX_BLOCK_SIZE, overflow: 'auto' }}
+      >
+        {ROLES.map((role) => (
+          <Button key={role} variant='quiet' onClick={() => setAnchor(null)}>
+            {role}
+          </Button>
+        ))}
+      </Menu>
+    </Stack>
+  );
+}
```
