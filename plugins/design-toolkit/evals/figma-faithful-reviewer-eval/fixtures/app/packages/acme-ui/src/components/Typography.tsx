// `Typography` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import type { ReactNode } from 'react';

import { Box, type SxObject } from '../system/Box';
import { componentOverrides } from '../theme/overrides';

type Variant =
  | 'pageTitle'
  | 'sectionTitle'
  | 'cardTitle'
  | 'fieldLabel'
  | 'body'
  | 'bodyStrong'
  | 'helper'
  | 'microLabel';

export interface TypographyProps {
  variant?: Variant;
  // Clips the text to one line and ends it with an ellipsis.
  ellipsis?: boolean;
  sx?: SxObject;
  children?: ReactNode;
}

const ELEMENT: Record<Variant, 'h1' | 'h2' | 'h3' | 'span' | 'p'> = {
  pageTitle: 'h1',
  sectionTitle: 'h2',
  cardTitle: 'h3',
  fieldLabel: 'span',
  body: 'p',
  bodyStrong: 'p',
  helper: 'p',
  microLabel: 'span',
};

const ellipsisStyles = {
  overflow: 'hidden',
  textOverflow: 'ellipsis',
  whiteSpace: 'nowrap',
};

export const Typography = ({ variant = 'body', ellipsis = false, sx, ...rest }: TypographyProps) => (
  <Box
    as={ELEMENT[variant]}
    data-variant={variant}
    sx={[componentOverrides.Typography.root, ellipsis && ellipsisStyles, sx]}
    {...rest}
  />
);
