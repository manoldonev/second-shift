// `Button` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import type { MouseEvent, ReactNode } from 'react';

import { Box, type SxObject } from '../system/Box';
import { componentOverrides } from '../theme/overrides';

export interface ButtonProps {
  variant?: 'primary' | 'secondary' | 'quiet';
  size?: 'small' | 'medium';
  type?: 'button' | 'submit' | 'reset';
  disabled?: boolean;
  onClick?: (event: MouseEvent<HTMLButtonElement>) => void;
  sx?: SxObject;
  children?: ReactNode;
}

export const Button = ({ variant = 'primary', size = 'medium', type = 'button', sx, ...rest }: ButtonProps) => (
  <Box
    as='button'
    type={type}
    data-variant={variant}
    sx={[componentOverrides.Button.root, size === 'small' && componentOverrides.ButtonSmall.root, sx]}
    {...rest}
  />
);
