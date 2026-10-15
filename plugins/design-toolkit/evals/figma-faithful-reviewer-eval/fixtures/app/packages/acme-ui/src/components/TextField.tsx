// `TextField` — part of the fictional `@acme/acme-ui` stand-in for the figma-faithful-reviewer eval.
// See ../../../../../design-tokens/acme-ui-catalog.md.
import { useId } from 'react';

import { Box, type SxObject } from '../system/Box';

export interface TextFieldProps {
  // A visible label, tied to the <input> by id.
  label?: string;
  value?: string;
  onChange?: (value: string) => void;
  placeholder?: string;
  // Attributes for the <input> element itself.
  inputProps?: Record<string, unknown>;
  // Lands on the FormControl root.
  sx?: SxObject;
  [rootProp: string]: unknown;
}

// The FormControl root is a <div> that wraps the optional label and the <input>.
export const TextField = ({ label, value, onChange, placeholder, inputProps, sx, ...rest }: TextFieldProps) => {
  const id = useId();
  return (
    <Box className='acme-FormControl' sx={sx} {...rest}>
      {label ? <label htmlFor={id}>{label}</label> : null}
      <input
        id={id}
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange?.(event.target.value)}
        {...inputProps}
      />
    </Box>
  );
};
