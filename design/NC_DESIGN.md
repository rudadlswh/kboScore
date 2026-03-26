# Design System Document

## 1. Overview & Creative North Star
**Creative North Star: The High-Performance Editorial**

This design system is built to transform the NC Dinos digital experience from a standard sports utility into a premium, athletic editorial. We move beyond "blue boxes" by embracing the visual language of high-end sports journalism—authoritative, high-performance, and deeply intentional. 

The system breaks the rigid, templated grid through **intentional asymmetry** and **tonal depth**. We leverage the Marine Navy and Gold palette not just as accents, but as structural layers that create an atmosphere of professional excellence. Key layout strategies include overlapping typography on athlete imagery, sophisticated surface layering, and a "Glass & Gradient" approach that adds soul to the performance data.

## 2. Colors & Atmospheric Depth

The color palette is anchored by `background` (#0f141b) and enriched by the Marine Navy (`primary_container`: #00275d) and Gold (`secondary`: #e3c191) tokens.

### The "No-Line" Rule
Sectioning must never be achieved with 1px solid borders. Boundaries are defined solely through background color shifts. For example, a content section using `surface_container_low` should sit directly against the `surface` background. This creates a modern, seamless flow that feels architectural rather than "boxed in."

### Surface Hierarchy & Nesting
Treat the UI as a series of nested physical layers. Use the surface-container tiers (Lowest to Highest) to define importance:
- **Baseline:** `surface` (#0f141b)
- **Deep Content Wells:** `surface_container_lowest` (#090e15)
- **Primary Cards:** `surface_container` (#1b2027)
- **Interactive Elevated Elements:** `surface_container_highest` (#30353d)

### The "Glass & Gradient" Rule
Floating elements (such as persistent player stats or navigation overlays) should utilize **Glassmorphism**. Apply a semi-transparent `surface_variant` with a 12px-20px backdrop-blur. 
To inject professional "soul," use subtle linear gradients for hero CTAs, transitioning from `primary` (#aec6ff) to `primary_container` (#00275d). This mimics the sheen of high-performance athletic gear.

## 3. Typography
We use **Inter** as our sole typeface, relying on the extreme contrast of the scale to create an editorial feel.

*   **Display (Display-LG/MD/SM):** Reserved for player names, scores, and major headlines. Use `on_surface` with tight letter-spacing (-0.02em) to convey a bold, "in-the-moment" athletic energy.
*   **Headlines (Headline-LG/MD):** Used for article titles and section headers. These should feel authoritative and provide the primary narrative structure.
*   **Body (Body-LG/MD):** Optimized for readability. Use `body-md` (0.875rem) for player bios and news articles, ensuring a comfortable line height (1.5).
*   **Labels (Label-MD/SM):** Specifically for technical data (ERA, Batting Average, Jersey Numbers). These utilize the `secondary` Gold token to highlight essential performance metrics against the Navy background.

## 4. Elevation & Depth

### The Layering Principle
Depth is achieved through **Tonal Layering** rather than structural shadows. Place a `surface_container_low` card on a `surface` background to create a soft, natural lift. This approach maintains the high-performance, sleek aesthetic of the NC Dinos brand.

### Ambient Shadows
When a floating effect is mandatory (e.g., Modals), use extra-diffused shadows.
- **Blur:** 24px - 40px
- **Opacity:** 6% - 10%
- **Color:** Use a tinted version of `on_surface` (deep navy-tinted) rather than pure black to mimic natural stadium lighting.

### The "Ghost Border" Fallback
If a border is required for accessibility, use the **Ghost Border**: the `outline_variant` token at 15% opacity. Standard 100% opaque borders are strictly forbidden as they clutter the premium editorial space.

## 5. Components

### Buttons
- **Primary:** Filled with `primary_container` (#00275d) or a Navy-to-Gold gradient. Text is `on_primary_container`. Roundedness is fixed at `lg` (8px).
- **Secondary:** Outlined with a "Ghost Border" using `secondary` (#e3c191) at 20% opacity. 
- **Tertiary:** Text-only using `primary_fixed_dim`, reserved for low-emphasis utility actions.

### Cards & Lists
**Strict Rule:** No divider lines. Separate list items using vertical white space from the Spacing Scale (e.g., `spacing-4` or `1rem`) or subtle alternating background shifts (`surface_container` to `surface_container_low`).

### Chips (Player Tags/Stats)
Small, high-contrast pills using `secondary_container` with `on_secondary_container` (Gold tones). These should feel like "badges" of honor on a player profile.

### Input Fields
Use `surface_container_highest` for the input track. The active state is indicated by a 2px `secondary` (Gold) bottom-border only, or a subtle glow, avoiding a full-perimeter active border.

### Signature Component: The "Stat Overlay"
A glassmorphic container (backdrop-blur 16px) that sits over player imagery, using `display-sm` for numbers and `label-sm` for metric titles, creating a "live broadcast" feel.

## 6. Do's and Don'ts

### Do
*   **Do** use asymmetrical layouts where text overlaps 20% of a high-resolution player image.
*   **Do** utilize the `spacing-16` (4rem) and `spacing-24` (6rem) tokens to create massive "breathing room" between major editorial sections.
*   **Do** use Gold (`secondary`) sparingly for "Moment of Glory" highlights and critical CTA accents.

### Don't
*   **Don't** use a standard 12-column grid for everything; offset content blocks to create a dynamic, magazine-like flow.
*   **Don't** use pure black (#000000) for shadows; always use a navy-tinted shadow to maintain the brand’s "Marine" color profile.
*   **Don't** use 100% opaque dividers; they break the immersion of the premium "layered" surface strategy.
*   **Don't** use rounded corners above or below the `lg` (8px) / `DEFAULT` (4px) standard for containers; the 8px radius is the "Signature Curve" of the system.