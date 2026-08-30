# Acme storefront design tokens (per-tenant branded theme)

Synthetic `design-tokens` extension for the `figma-faithful-reviewer` eval, describing a fictional
organization. Sibling to `acme-ui-design-tokens-console.md` (fixed theme) and `acme-ui-catalog.md`
in this directory. **Applies to:** files under `apps/storefront/`.

**The storefront does NOT use a static theme.** It builds a **per-tenant branded theme at
runtime** from the merchant's branding record plus the embedding host's settings. So — unlike the
console — there is **no fixed px↔unit or hex↔token table** to look values up in. The values are
branded and host-relative; the discipline is to use the **abstractions**, and never to write a
literal.

## What is branded / host-relative

- **`brandColor`, `surfaceColor`** — from the merchant's branding record, per tenant at runtime.
- **`fontFamily`, `headingFontFamily`** — from the merchant's branding record.
- **`hostRootFontSize`** — in web-component mode the theme adopts the **host page's** root font
  size; standalone and iframe flavors fall back to a 16px default. So `rem` resolves to a
  different number of physical pixels per embedding.
- **`direction`** — `ltr` / `rtl`, from the shopper's selected locale. The storefront is
  RTL-capable.

## Rules

1. **Color — never hardcode a hex or `rgb()`.** Use palette paths (`brand.main`,
   `background.surface`, `background.default`, `text.primary`, `text.secondary`, `positive.main`,
   `caution.main`, `critical.main`, …). `brand` and `background` are **merchant-branded**; a
   hardcoded hex defeats per-tenant theming. This is the strongest storefront rule — stronger than
   the console's, where the palette is fixed and the hex at least resolves to the right token.
2. **Sizing — use `theme.typography.pxToRem(px)`, never a hardcoded `rem` or a raw `px`.** `rem`
   is host-controlled in web-component mode. Applies to one-off `width` / `height` / `minWidth` /
   `fontSize` and friends.
3. **Spacing — use theme unit numbers** (`gap`, `rowGap`, `padding*`, `margin*` as numbers). The
   spacing factory scales with the host root font size, so think in **scale units**, not px: the
   px-equivalent varies by embedding. Never a `px` or `rem` string in a spacing prop.
4. **Font family — never hardcode.** It is branded; inherit it through `Typography` and the
   catalog components, never a literal family string in `sx`.
5. **Typography — use `<Typography variant>`**, never a raw `fontSize` / `fontWeight` /
   `fontFamily`. The storefront ramp reuses the console's variant names.
6. **Direction — use logical `sx` props** (`paddingInlineStart`, `marginBlockEnd`,
   `insetInlineStart`), never physical (`paddingLeft`, `marginTop`, `left`) and never the
   shorthand aliases (`p`, `pl`, `mt`, `bgcolor`). The storefront renders RTL for some locales, so
   this is a **correctness** rule here, not a style preference.

## Distribution flavors (all three must work)

The storefront ships standalone, as an iframe embed, and as a web component (`<acme-store>`). The
web-component flavor is why `rem` is host-controlled and `pxToRem` is non-negotiable — never
assume a fixed root font size.

## When this doc does NOT apply (limits)

1. **It does not enforce itself** — a reader has to check the actual `sx` usage against these
   rules; the doc alone does not prevent a hardcoded hex.
2. **No value lookup** — because the palette and the rem base are runtime and branded, there is no
   "this px → that unit" or "this hex → that path" table. The rule is always "use the
   abstraction", and the rendered value is not statically knowable.
3. **Color-correctness against the design** still needs the Figma node plus the tenant's branding,
   and is out of scope for a static read: it can confirm a path is used, never that the branded
   result matches the mock.
