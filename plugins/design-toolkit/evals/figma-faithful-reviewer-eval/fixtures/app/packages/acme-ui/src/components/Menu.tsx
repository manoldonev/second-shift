// `Menu` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import type { ReactNode } from 'react';
import { createPortal } from 'react-dom';

import { Box, type SxObject } from '../system/Box';
import { componentOverrides } from '../theme/overrides';

export interface MenuProps {
  open: boolean;
  anchorEl?: HTMLElement | null;
  onClose?: () => void;
  // Lands on the menu paper.
  sx?: SxObject;
  children?: ReactNode;
}

// Renders the paper in a portal at the end of document.body, positioned against `anchorEl`.
export const Menu = ({ open, anchorEl, onClose, sx, children }: MenuProps) =>
  open
    ? createPortal(
        <Box
          role='menu'
          data-anchored={anchorEl ? 'true' : 'false'}
          onKeyDown={(event: KeyboardEvent) => (event.key === 'Escape' ? onClose?.() : undefined)}
          sx={[componentOverrides.Menu.paper, sx]}
        >
          {children}
        </Box>,
        document.body,
      )
    : null;
