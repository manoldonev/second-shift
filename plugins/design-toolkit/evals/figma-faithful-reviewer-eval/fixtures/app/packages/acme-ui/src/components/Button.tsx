// `Button` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import type { MouseEvent, ReactNode } from 'react';

import { Box, type SxObject } from '../system/Box';
import { componentOverrides } from '../theme/overrides';

export interface ButtonProps {
  variant?: 'primary' | 'secondary' | 'quiet';
  type?: 'button' | 'submit' | 'reset';
  disabled?: boolean;
  onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  sx?: SxObject;
  children?: ReactNode;
}

export const Button = ({ variant = 'primary', type = 'button', sx, ...rest }: ButtonProps) => (
  <Box
    as='button'
    type={type}
    data-variant={variant}
    sx={[componentOverrides.Button.root, sx]}
    {...rest}
  />
);
