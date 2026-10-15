// `Box` and the `sx` resolver that every `@acme/acme-ui` component renders through. Part of the
// fictional stand-in for the figma-faithful-reviewer eval — see
// ../../../../../design-tokens/acme-ui-catalog.md.
import type { ElementType, ReactNode } from 'react';

export type SxObject = Record<string, unknown>;
export type SxEntry = SxObject | false | null | undefined;
export type SxProps = SxObject | SxEntry[];

export interface BoxProps {
  as?: ElementType;
  sx?: SxProps;
  children?: ReactNode;
  [prop: string]: unknown;
}

// Flattens an `sx` array into one style object, left to right. A later entry wins on every key
// that an earlier entry also sets.
export function resolveSx(sx: SxProps | undefined): SxObject {
  if (!sx) return {};
  if (!Array.isArray(sx)) return sx;
  return sx.reduce<SxObject>((merged, entry) => (entry ? { ...merged, ...entry } : merged), {});
}

// Theme-unit and palette-path translation; omitted from this stand-in.
declare function toClassName(style: SxObject): string;

export function Box({ as: Component = 'div', sx, ...rest }: BoxProps) {
  return <Component className={toClassName(resolveSx(sx))} {...rest} />;
}
