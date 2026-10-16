// Component theme overrides that ship with `@acme/acme-ui`. Part of the fictional stand-in for the
// figma-faithful-reviewer eval — see ../../../../../design-tokens/acme-ui-catalog.md.
//
// Each component lists its entry here first in its `sx` array and the caller's `sx` after it
// (see ../system/Box.tsx). A bare spacing number is a theme spacing unit (4px).
export const componentOverrides = {
  Button: {
    root: {
      textTransform: 'none',
      whiteSpace: 'nowrap',
      paddingInline: 4,
      minBlockSize: '36px',
    },
  },
  Tag: {
    root: {
      textTransform: 'uppercase',
      paddingInline: 2,
      borderRadius: '999px',
    },
  },
  Menu: {
    paper: {
      zIndex: 1300,
      minInlineSize: '12rem',
      paddingBlock: 1,
    },
  },
  Typography: {
    root: {
      margin: 0,
    },
  },
  // Applied by Button only when size='small'.
  ButtonSmall: { root: { paddingInline: 2, minBlockSize: '28px' } },
} as const;
