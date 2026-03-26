# Design System Document

## 1. Overview & Creative North Star: "Heroes Pride"

This design system is engineered to capture the aggressive, high-octane energy of KBO baseball. Moving beyond the "utility-first" approach of standard sports apps, we are building a digital stadium experience.

**The Creative North Star: "Heroes Pride"**
Our vision is "Modern Brutalism meets Neon Intensity." We break the standard grid by using intentional asymmetry and high-contrast typography scales. The layout should feel like a premium editorial sports magazine—fast-paced, authoritative, and sharp. By utilizing deep burgundy depths and electric magenta accents, we create a high-energy environment that celebrates the grit and victory of the Kiwoom Heroes.

---

## 2. Colors

The palette is built on a foundation of deep, layered blacks and burgundies, designed to make the accent magenta "pop" with an almost radioactive intensity.

### Palette Strategy
*   **Primary Burgundy (`#570514`):** Used for deep immersion. This isn't just a color; it’s the heritage. Use it for major containers and hero sections.
*   **Secondary Magenta (`#E3007E`):** The "Pulse." Reserve this for critical actions, live scores, and active states. It should feel like a neon light in a dark alley.
*   **Neutrals:** We use a range of Surface containers (`#131313` to `#353534`) to create depth without using lines.

### The "No-Line" Rule
**Prohibit 1px solid borders for sectioning.** Boundaries must be defined solely through background color shifts or tonal transitions.
*   *Example:* A `surface-container-low` section sitting on a `surface` background provides all the separation the eye needs.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. 
*   **Level 0:** `surface` (`#131313`) – The base field.
*   **Level 1:** `surface-container-low` (`#1c1b1b`) – Section groupings.
*   **Level 2:** `surface-container-high` (`#2a2a2a`) – Interactive cards.
Each inner container should use a slightly higher or lower tier to define its importance, creating a "nested" depth that feels sophisticated and architectural.

### The "Glass & Gradient" Rule
To elevate the experience, use Glassmorphism for floating elements (Backdrop-blur: 20px) using semi-transparent `surface-variant` colors. Main CTAs should utilize a subtle linear gradient transitioning from `primary` to `primary_container` to add visual "soul" and dimension.

---

## 3. Typography

The typography is the engine of the "Heroes Pride" identity. We pair the technical precision of **Inter** with the aggressive, wide stance of **Space Grotesk**.

*   **Display & Headlines (Space Grotesk):** High-impact, bold, and high-performance. Use `display-lg` (3.5rem) for score updates and player names to create an "in-your-face" editorial feel.
*   **Titles & Body (Inter):** Clean and legible. Inter provides the "Technical Director" voice—reliable and sharp.
*   **Scale Tonal Shift:** Use `on_surface_variant` (muted) for labels and `on_surface` (bright silver) for active content to create a natural hierarchy without changing font weight.

---

## 4. Elevation & Depth

We eschew traditional drop shadows in favor of **Tonal Layering**.

*   **The Layering Principle:** Stacking surface-container tiers creates a natural lift. A `surface-container-highest` card placed on a `surface-dim` background creates professional contrast without the "muddy" look of standard shadows.
*   **Ambient Shadows:** If a floating element (like a FAB or Modal) requires a shadow, use a large blur (32px+) at 4% opacity. The shadow color must be a tinted version of the surface color—never pure black.
*   **The "Ghost Border" Fallback:** If accessibility requires a border, use the `outline_variant` token at **10-20% opacity**. 100% opaque borders are strictly forbidden.

---

## 5. Components

### Buttons
*   **Primary:** High-saturation Magenta (`secondary_container`) with `on_secondary_container` text. 4px roundedness (`DEFAULT`).
*   **Secondary:** Ghost-style. No fill, `outline` border at 20% opacity. 
*   **State:** On hover, apply a slight glow effect using the Magenta color to mimic a neon tube.

### Cards & Lists
*   **No Dividers:** Forbid the use of divider lines. Use vertical white space (Scale `6` or `8`) or subtle background shifts between `surface-container-low` and `surface-container-high`.
*   **Edge Treatment:** 8px (`lg`) corner radius for player cards; 4px (`DEFAULT`) for technical data tables.

### Interactive Elements
*   **Chips:** Use `tertiary_container` for unselected and `secondary` for selected states. 
*   **Input Fields:** Use `surface_container_highest` as the background. No border. On focus, a bottom-only 2px bar of Magenta (`secondary`).

### App-Specific Components
*   **Live Score Ticker:** A full-bleed `surface_container_lowest` bar with high-contrast `display-sm` typography.
*   **Win-Probability Meter:** A gradient bar transitioning from `primary_container` to `secondary`.

---

## 6. Do's and Don'ts

### Do
*   **DO** use extreme typographic scale. Make the scores massive and the labels small and techy.
*   **DO** embrace "Dark Matter." Let the dark background breathe; white space in a dark theme is the key to a premium feel.
*   **DO** use Magenta sparingly but intensely. It is a "signal" color, not a background color.

### Don't
*   **DON'T** use 1px solid white/grey dividers. It breaks the "Heroes Pride" immersion.
*   **DON'T** use rounded corners above 12px. We want "Sharp & Edgy," not "Soft & Bubbly."
*   **DON'T** use pure #000000 for backgrounds. Use the `surface` tokens to maintain depth and allow for ambient light layering.