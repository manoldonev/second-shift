// `Tag` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import type { ReactNode } from 'react';

import { Box, type SxObject } from '../system/Box';
import { componentOverrides } from '../theme/overrides';

export interface TagProps {
  tone?: 'neutral' | 'positive' | 'caution' | 'critical';
  sx?: SxObject;
  children?: ReactNode;
}

export const Tag = ({ tone = 'neutral', sx, ...rest }: TagProps) => (
  <Box as='span' data-tone={tone} sx={[componentOverrides.Tag.root, sx]} {...rest} />
);
