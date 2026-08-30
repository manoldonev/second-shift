```diff
diff --git a/apps/storefront/src/features/orders/OrderFilterBar.tsx b/apps/storefront/src/features/orders/OrderFilterBar.tsx
index 8f0c2a1..1d33b90 100644
--- a/apps/storefront/src/features/orders/OrderFilterBar.tsx
+++ b/apps/storefront/src/features/orders/OrderFilterBar.tsx
@@ -1,18 +1,60 @@
-import { Stack, Tag } from '@acme/acme-ui';
+import { Stack, Tag, Select, IconButton, Typography } from '@acme/acme-ui';
 
 import { useOrderFilters } from '../../hooks/useOrderFilters';
 
 export function OrderFilterBar() {
-  const { status } = useOrderFilters();
+  const { status, setStatus, range, setRange, activeTags, clearTag } = useOrderFilters();
 
   return (
-    <Stack direction='row'>
-      <Tag>{status}</Tag>
-    </Stack>
+    <Stack
+      direction='row'
+      sx={{
+        alignItems: 'center',
+        marginTop: 4,
+        paddingLeft: 6,
+        paddingRight: 6,
+        bgcolor: 'background.sunken',
+        borderRadius: 2,
+      }}
+    >
+      <Typography variant='fieldLabel' sx={{ marginRight: 3 }}>
+        Filter
+      </Typography>
+
+      <Select
+        value={status}
+        onChange={(v) => setStatus(v)}
+        sx={{ minWidth: (t) => t.typography.pxToRem(180) }}
+      >
+        <option value='all'>All orders</option>
+        <option value='open'>Open</option>
+        <option value='shipped'>Shipped</option>
+      </Select>
+
+      <Select
+        value={range}
+        onChange={(v) => setRange(v)}
+        sx={{ marginLeft: 3, minWidth: (t) => t.typography.pxToRem(160) }}
+      >
+        <option value='30d'>Last 30 days</option>
+        <option value='90d'>Last 90 days</option>
+      </Select>
+
+      <Stack direction='row' gap={2} sx={{ marginLeft: 'auto' }}>
+        {activeTags.map((tag) => (
+          <Tag key={tag} onDismiss={() => clearTag(tag)}>
+            {tag}
+          </Tag>
+        ))}
+      </Stack>
+
+      <IconButton
+        aria-label='Reset filters'
+        sx={{ position: 'absolute', top: 8, right: 8 }}
+      />
+    </Stack>
   );
 }
```
