```diff
diff --git a/apps/console/src/features/billing/PlanSummaryCard.tsx b/apps/console/src/features/billing/PlanSummaryCard.tsx
new file mode 100644
index 0000000..2b47dd1
--- /dev/null
+++ b/apps/console/src/features/billing/PlanSummaryCard.tsx
@@ -0,0 +1,66 @@
+import { Banner, Button, Card, Stack, Tag, Typography } from '@acme/acme-ui';
+
+import { usePlanSummary } from '../../hooks/usePlanSummary';
+
+// 14px optical nudge so the seat count aligns with the plan name's cap height rather than
+// its bounding box; 3.5 spacing units, off the 4px scale.
+const SEAT_COUNT_OPTICAL_INSET = '14px';
+
+export function PlanSummaryCard({ workspaceId }: { workspaceId: string }) {
+  const { plan, seatsUsed, seatsIncluded, renewsOn, isTrial } = usePlanSummary(workspaceId);
+
+  return (
+    <Card elevation={0} sx={{ borderColor: 'border.default' }}>
+      <Stack gap={6} sx={{ paddingInline: 6, paddingBlock: 6 }}>
+        <Stack direction='row' gap={3} sx={{ alignItems: 'center' }}>
+          <Typography variant='sectionTitle'>{plan.name}</Typography>
+          {isTrial ? <Tag tone='caution'>Trial</Tag> : null}
+        </Stack>
+
+        {isTrial ? (
+          <Banner tone='caution'>Your trial ends on {renewsOn}.</Banner>
+        ) : null}
+
+        <Stack gap={2}>
+          <Typography variant='fieldLabel'>Seats</Typography>
+          <Typography
+            variant='body'
+            sx={{ color: 'text.secondary', paddingInlineStart: SEAT_COUNT_OPTICAL_INSET }}
+          >
+            {seatsUsed} of {seatsIncluded} in use
+          </Typography>
+        </Stack>
+
+        <Stack
+          direction='row'
+          sx={{
+            justifyContent: 'space-between',
+            alignItems: 'center',
+            borderBlockStart: '1px solid',
+            borderColor: 'border.subtle',
+            paddingBlockStart: 4,
+          }}
+        >
+          <Typography variant='helper' sx={{ color: 'text.secondary' }}>
+            Renews {renewsOn}
+          </Typography>
+          <Button variant='secondary'>Change plan</Button>
+        </Stack>
+      </Stack>
+    </Card>
+  );
+}
```
