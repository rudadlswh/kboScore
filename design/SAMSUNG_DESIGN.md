# Design System Strategy: The Championship Blueprint

## 1. Overview & Creative North Star
This design system serves as the digital home for the Samsung Lions. It is not merely a sports portal; it is a high-performance, editorial-grade interface that reflects the prestige of a dynasty.

**Creative North Star: "The Prestigious Athlete"**
The aesthetic direction moves away from the "cluttered" nature of traditional sports apps. Instead, it adopts the language of luxury automotive and high-end editorial design. We prioritize breathing room, intentional asymmetry, and tonal depth over rigid grids and harsh borders. The experience should feel like a premium stadium suite—clean, modern, and authoritative.

By leveraging sharp typography scales and overlapping elements, we create a sense of forward motion and "High Performance," mirroring the speed and precision of the game.

---

## 2. Colors & Signature Surfaces
The color palette is rooted in Royal Blue and Silver, but its application is modern and nuanced, avoiding a "flat" corporate feel.

### Color Tokens
*   **Primary Core:** `primary` (#004e8b) & `primary_container` (#0066b3). These represent the heart of the brand. Use the container variant for actionable surfaces.
*   **The Silver Secondary:** `secondary_fixed_dim` (#c6c6c6). This is our "Steel" token, used for prestigious accents and metallic-feel containers.
*   **Surface Depth:** `surface` (#f7f9ff) serves as the stadium floor.

### The Rules of Engagement
*   **The "No-Line" Rule:** 1px solid borders are strictly prohibited for sectioning. Use background shifts to define boundaries. A `surface_container_low` section sitting on a `surface` background is the preferred method for creating containment.
*   **Surface Hierarchy & Nesting:** Treat the UI as physical layers. An athlete's stat card should use `surface_container_lowest` (#ffffff) to "pop" off a `surface_container` (#eceef3) background. This creates a soft, natural depth.
*   **The "Glass & Gradient" Rule:** For floating headers or game-day overlays, use Glassmorphism. Apply `surface` with 80% opacity and a 20px backdrop-blur. 
*   **Signature Textures:** For high-impact areas like Hero banners, use a subtle linear gradient from `primary` (#004e8b) to `primary_container` (#0066b3) at a 135-degree angle to add a "sheen" reminiscent of a professional jersey.

---

## 3. Typography
We utilize a dual-font strategy to balance aggressive performance with clean readability.

*   **Display & Headline (Manrope):** Chosen for its geometric precision. Use `display-lg` (3.5rem) for scoreboards and `headline-lg` (2rem) for game titles. This font conveys the "Modern" and "Prestigious" pillars.
*   **Body & Titles (Inter):** The workhorse. Inter provides maximum legibility for player bios, news articles, and ticket details.
*   **Editorial Intent:** Use `display-md` with a negative letter-spacing (-0.02em) for player numbers and key metrics to create a bespoke, high-end feel.

---

## 4. Elevation & Depth
In this system, elevation is an environmental property, not a stylistic choice.

*   **The Layering Principle:** Depth is achieved by "stacking" surface-container tiers. Never use a shadow where a color shift can work.
*   **Ambient Shadows:** When a card must float (e.g., a "Buy Tickets" modal), use an ultra-diffused shadow: `offset-y: 8px, blur: 24px, color: rgba(0, 78, 139, 0.06)`. This uses a blue tint rather than grey to mimic natural, ambient light.
*   **The "Ghost Border" Fallback:** If a border is required for accessibility, use `outline_variant` (#c1c7d3) at **15% opacity**. It should be felt, not seen.
*   **Asymmetric Overlaps:** To break the "template" look, allow player imagery to overlap the boundary between a `surface` and a `primary_container` section. This adds a "Signature" custom feel.

---

## 5. Components

### Buttons
*   **Primary:** Solid `primary_container` with `on_primary` text. Use `roundedness.md` (0.375rem).
*   **Secondary:** `surface_container_high` background with `primary` text. No border.
*   **Interaction:** On hover, increase the surface brightness by 5%; do not change the hue.

### Cards & News Lists
*   **Rule:** Forbid divider lines. Use `spacing.8` (2rem) of vertical white space to separate news items.
*   **Visual Structure:** Use a `surface_container_lowest` card with a `secondary_fixed_dim` (Silver) left-accent bar (4px) to denote "Featured" content.

### Inputs & Fields
*   **Styling:** Filled style using `surface_container_high`. Use `on_surface_variant` for labels.
*   **States:** On focus, transition the background to `surface_container_highest` and add a 2px `primary` bottom-border only.

### Signature Component: The "Live Score" Widget
*   **Design:** A Glassmorphic container (`surface` @ 70% + blur) with `display-sm` typography for scores. Use `primary_fixed` for the "Live" indicator to ensure it glows against the silver/blue background.

---

## 6. Do's and Don'ts

### Do
*   **Do** use asymmetrical spacing. If the left margin is `spacing.10`, try a right margin of `spacing.6` for editorial layouts.
*   **Do** use large player photography that bleeds off the edge of the screen.
*   **Do** prioritize the Silver (`secondary_fixed_dim`) for small, high-contrast details like icons or metadata labels.

### Don't
*   **Don't** use pure black (#000000). Use `on_background` (#181c20) for all text to maintain the "Clean" aesthetic.
*   **Don't** use 1px dividers between list items. The `surface` hierarchy is your tool for separation.
*   **Don't** use default shadows. If it looks like a standard web shadow, it’s too heavy. It should feel like air.