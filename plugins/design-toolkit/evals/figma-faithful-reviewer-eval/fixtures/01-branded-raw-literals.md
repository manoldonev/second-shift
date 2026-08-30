```diff
diff --git a/apps/storefront/src/features/checkout/OrderSummaryCard.tsx b/apps/storefront/src/features/checkout/OrderSummaryCard.tsx
index 3a91f0c..b7e2d14 100644
--- a/apps/storefront/src/features/checkout/OrderSummaryCard.tsx
+++ b/apps/storefront/src/features/checkout/OrderSummaryCard.tsx
@@ -1,12 +1,58 @@
-import { Card, Stack, Typography } from '@acme/acme-ui';
+import { Card, Stack, Typography, Button } from '@acme/acme-ui';
 
 import { useCheckoutTotals } from '../../hooks/useCheckoutTotals';
+import { formatMoney } from '../../utils/formatMoney';
 
 export function OrderSummaryCard({ orderId }: { orderId: string }) {
-  const { subtotal } = useCheckoutTotals(orderId);
+  const { subtotal, shipping, tax, total } = useCheckoutTotals(orderId);
 
   return (
-    <Card>
-      <Typography variant='cardTitle'>Order summary</Typography>
-    </Card>
+    <Card
+      elevation={0}
+      sx={{
+        width: '320px',
+        borderColor: '#D6DBE3',
+        backgroundColor: '#FFFFFF',
+      }}
+    >
+      <Stack gap={4} sx={{ paddingInline: 6, paddingBlock: 6 }}>
+        <Typography
+          sx={{ fontSize: '18px', fontWeight: 600, fontFamily: 'Inter, sans-serif' }}
+        >
+          Order summary
+        </Typography>
+
+        <Stack gap={2}>
+          <SummaryRow label='Subtotal' value={formatMoney(subtotal)} />
+          <SummaryRow label='Shipping' value={formatMoney(shipping)} />
+          <SummaryRow label='Tax' value={formatMoney(tax)} />
+        </Stack>
+
+        <Stack
+          direction='row'
+          sx={{
+            justifyContent: 'space-between',
+            borderBlockStart: '1px solid #EDF0F4',
+            paddingBlockStart: 4,
+          }}
+        >
+          <Typography variant='bodyStrong'>Total</Typography>
+          <Typography variant='bodyStrong' sx={{ color: '#12161C' }}>
+            {formatMoney(total)}
+          </Typography>
+        </Stack>
+
+        <Button
+          fullWidth
+          sx={{ minHeight: '2.75rem', backgroundColor: '#1F6FEB' }}
+        >
+          Place order
+        </Button>
+      </Stack>
+    </Card>
   );
 }
+
+function SummaryRow({ label, value }: { label: string; value: string }) {
+  return (
+    <Stack direction='row' sx={{ justifyContent: 'space-between' }}>
+      <Typography variant='body' sx={{ color: '#5A6472' }}>{label}</Typography>
+      <Typography variant='body'>{value}</Typography>
+    </Stack>
+  );
+}
```
