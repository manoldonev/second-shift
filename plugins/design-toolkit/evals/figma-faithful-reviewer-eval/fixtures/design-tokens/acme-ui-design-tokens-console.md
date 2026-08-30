# Acme `acme-ui` design tokens (console — fixed theme)

Synthetic `design-tokens` extension for the `figma-faithful-reviewer` eval, describing a fictional
organization. Sibling to `acme-ui-catalog.md` and `acme-ui-design-tokens-storefront.md` in this
directory.

Translates Figma values into `acme-ui` tokens for **console** FE work, so spacing/color/type
values come from a table rather than from eyeballing a screenshot.

**Theme:** `console` (this app only — the storefront app builds a branded theme at runtime and
this table does not apply there). **Applies to:** files under `apps/console/`.

**How to use.** When a Figma node dump gives a px / hex / type value, look it up here and write
the **token**, never the literal. If a value is not on a scale below, read "When this doc does not
apply".

---

## Base facts

- Root `font-size` is left at the browser default → **1rem = 16px**.
- Spacing factory: `theme.spacing(n)` returns `0.25 * n` rem → **1 spacing unit = 4px**.
- So an `sx` spacing number `n` renders `n × 4` px. `gap={6}` is 24px, **not** 48px.
- Figma `px → sx number` = **`px ÷ 4`**.

---

## Spacing scale

The Figma `--gap/*` scale maps 1:1 onto the theme's spacing steps. Use the `sx` number for
`gap` / `rowGap` / `padding*` / `margin*`.

| Figma token  | px | `sx` number |
| ------------ | -- | ----------- |
| `--gap/3xs`  | 2  | `0.5`       |
| `--gap/2xs`  | 4  | `1`         |
| `--gap/xs`   | 8  | `2`         |
| `--gap/sm`   | 12 | `3`         |
| `--gap/md`   | 16 | `4`         |
| `--gap/lg`   | 24 | `6`         |
| `--gap/xl`   | 40 | `10`        |
| `--gap/2xl`  | 64 | `16`        |

**Rules.**

- Use logical, full-name props (`paddingInlineStart`, `paddingBlockEnd`, `marginBlockStart`,
  `insetInlineStart`) — never physical (`paddingLeft`, `marginTop`) and never the shorthand
  aliases (`p`, `pt`, `px`, `m`, `mb`, `bgcolor`).
- `insetBlockStart` / `top` / `insetInlineEnd` are **not** spacing-aware: a bare number there
  serializes to `px`. Write `'16px'` explicitly, or compute `theme.spacing(4)`.
- An off-scale value (e.g. a 14px optical nudge, which is 3.5 units) is acceptable **only** as a
  named module-level constant carrying a one-line comment that says why. A bare inline off-scale
  literal is a finding.

---

## Color palette

Write the palette path, never the hex.

| Figma / hex                       | Token path                              |
| --------------------------------- | --------------------------------------- |
| `#12161C`                         | `text.primary`                          |
| `#5A6472`                         | `text.secondary`                        |
| `#8D96A5`                         | `text.disabled`                         |
| `#D6DBE3`                         | `border.default`                        |
| `#EDF0F4`                         | `border.subtle` / `background.sunken`   |
| `#FFFFFF`                         | `background.surface`                    |
| `#F7F9FB`                         | `background.default`                    |
| `#1F6FEB` / `#DCE9FD` / `#12459A` | `brand.main` / `.tint` / `.deep`        |
| `#1B7F4B` / `#D8F0E2` / `#0F5231` | `positive.main` / `.tint` / `.deep`     |
| `#B4620A` / `#FBEAD4` / `#7A4106` | `caution.main` / `.tint` / `.deep`      |
| `#C0342F` / `#FADCDB` / `#82211D` | `critical.main` / `.tint` / `.deep`     |

---

## Typography ramp

Use `<Typography variant='…'>`, never a raw `fontSize` / `fontWeight` / `fontFamily`.

| Variant        | Weight      | Size | Line-height | Figma text style       |
| -------------- | ----------- | ---- | ----------- | ---------------------- |
| `pageTitle`    | bold (700)  | 26px | 32px        | `Text/Page title`      |
| `sectionTitle` | semi (600)  | 20px | 26px        | `Text/Section title`   |
| `cardTitle`    | semi (600)  | 16px | 22px        | `Text/Card title`      |
| `fieldLabel`   | semi (600)  | 13px | 18px        | `Text/Field label`     |
| `body`         | normal(400) | 15px | 22px        | `Text/Body`            |
| `bodyStrong`   | semi (600)  | 15px | 22px        | `Text/Body strong`     |
| `helper`       | normal(400) | 13px | 18px        | `Text/Helper`          |
| `microLabel`   | semi (600)  | 11px | 14px        | `Text/Micro`           |

**Note:** the Figma-style → variant mapping is a name/size match, not arithmetic. A size that is
not in the ramp (a one-off 17px) has no variant — flag it, do not force-fit it.

---

## Component defaults that bite

- `Card` renders a resting elevation shadow **and** a 1px border. A flat card in the design needs
  `elevation={0}`; the border is overridden through `sx`.
- `TextField` and `Select` are full-width by default. A design showing a narrow control needs an
  explicit width.
- `Banner` reserves inline-start space for a status icon even when none is passed.

---

## When this doc does NOT apply (read before trusting it)

1. **It does not enforce itself.** It is a lookup table. The implementation step still has to pull
   the node's variable definitions and translate through this doc; skipping that is the failure
   this file exists to make visible, and the file alone does not prevent it.
2. **Detached / literal Figma values.** A node that emits a bare `16px` instead of a `--gap/md`
   reference still has to be confirmed on-scale before the row is trusted.
3. **Off-scale values** — spacing that does not divide into the scale, a hex outside the palette,
   a size outside the ramp — need judgment plus a named constant. The doc cannot resolve them.
4. **Layout and structural fidelity** — flex direction, widths, alignment, responsive behavior —
   is not a token value, and this doc says nothing about it.
5. **The storefront app.** Different theme, different rules; see the sibling file.
