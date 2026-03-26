# Design System Strategy: The Landers Field

## 1. Overview & Creative North Star
The Creative North Star for this design system is **"The Landers Field."** In professional baseball, the field is a place of absolute precision and explosive power. This system rejects the generic "utility app" look in favor of a high-end editorial experience that mirrors a premium stadium atmosphere.

To break the "template" aesthetic, we utilize **Intentional Asymmetry** and **Tonal Depth**. Rather than placing content in centered, predictable boxes, we use staggered layouts and overlapping typography to create a sense of forward motion. We treat the digital interface not as a flat screen, but as a series of curated layers—using high-contrast typography scales and varying surface containers to guide the fan's eye with the same speed as a fastball.

---

## 2. Color Mastery & The "No-Line" Rule
This system is defined by its sophisticated use of red and grey, moving beyond flat applications to create a "living" interface.

*   **Primary Deep Red (#CE0E2D):** Used as the heartbeat of the app. It signifies action, live scores, and high-intensity moments. Use the `primary_container` (#ce0e2d) for high-impact zones.
*   **Secondary Silver (#A0A0A0):** This is our "mechanical" color, representing the precision of equipment and the metallic sheen of the stadium.
*   **The "No-Line" Rule:** To maintain a premium editorial feel, **1px solid borders are strictly prohibited for sectioning.** Boundaries must be defined solely through background color shifts. For example, a `surface_container_low` (#f3f3f3) section should sit directly against a `surface` (#f9f9f9) background.
*   **Surface Hierarchy & Nesting:** Treat the UI as physical layers. Use the `surface_container` tiers to create depth. A `surface_container_lowest` (#ffffff) card should be "nested" within a `surface_container_high` (#e8e8e8) section to define importance through contrast rather than lines.
*   **The "Glass & Gradient" Rule:** For floating stats or player cards, use Glassmorphism. Apply a `surface` color at 80% opacity with a `backdrop-blur` effect. For main CTAs, use a subtle linear gradient from `primary` (#a3001f) to `primary_container` (#ce0e2d) at a 135-degree angle to add "visual soul."

---

## 3. Typography: The Editorial Engine
We use **Inter** not just for legibility, but as a tool for architectural strength. The hierarchy is designed to feel like a modern sports magazine.

*   **Display (lg/md/sm):** These are your "Power" ranks. Use `display-lg` (3.5rem) for score updates or home run counts. These should be set with tight letter-spacing (-0.02em) to feel impactful.
*   **Headlines & Titles:** Used for news articles and player names. `headline-lg` (2rem) provides an authoritative voice.
*   **The Contrast Rule:** Always pair a large `display-sm` stat with a `label-sm` (0.6875rem) in all-caps using the `on_surface_variant` (#5c3f3e) color. This "Big/Small" pairing is the hallmark of high-end sports design.
*   **Body:** Keep `body-md` (0.875rem) for play-by-play descriptions, ensuring a line height of 1.5 to maintain breathability amidst the data-heavy content.

---

## 4. Elevation & Depth: Tonal Layering
In "The Landers Field," we do not use heavy shadows that muddy the interface. We use light.

*   **The Layering Principle:** Depth is achieved by "stacking" the `surface-container` tiers. A `surface_container_lowest` card placed on a `surface_dim` background creates a natural, soft lift.
*   **Ambient Shadows:** If a floating element (like a FAB or a modal) requires a shadow, use a large 32px blur with only 6% opacity. Use a tinted shadow—a dark version of the `primary` color (#410006) instead of pure black—to make the shadow feel like a natural reflection of the brand color.
*   **The "Ghost Border" Fallback:** If a divider is mandatory for accessibility, use the `outline_variant` (#e6bdbb) at 15% opacity. Never use 100% opaque lines.
*   **Glassmorphism:** Use `surface_container_lowest` at 70% opacity with a 12px background blur for navigation bars to allow the field colors to bleed through as the user scrolls.

---

## 5. Components & Signature Patterns

### Buttons
*   **Primary:** Background: `primary_container` (#ce0e2d); Shape: `8px` (`DEFAULT`). Use a subtle inner-glow (top white border 10% opacity) to simulate a "3D" precision-milled edge.
*   **Secondary:** Background: `secondary_container` (#e0dfdf); Text: `on_secondary_container` (#626363).
*   **Tertiary:** No background. Text uses `primary` (#a3001f) with an icon for "view all" actions.

### Cards & Stats (The Core of the App)
*   **Strict Rule:** No dividers. Use `spacing.8` (2rem) of vertical white space to separate news items.
*   **Live Score Card:** Use `surface_container_highest` (#e2e2e2) for the container. The "Live" indicator should pulse using a `primary` (#a3001f) glow.

### Specialized Components
*   **The "Heat Map" Chip:** For player pitch zones, use chips with `tertiary_fixed` (#bde9ff) backgrounds to contrast against the red-dominant palette.
*   **The Scoreboard Header:** A full-bleed `surface_dim` (#dadada) area that uses `display-lg` typography, overlapping the edge of the container to break the grid.

---

## 6. Do's and Don'ts

### Do:
*   **Use Massive Scale:** Don't be afraid to use `display-lg` for a single-digit inning number.
*   **Embrace Negative Space:** Let the `background` (#f9f9f9) breathe. High-performance design feels fast because it isn't cluttered.
*   **Layer Surfaces:** Use `surface_container_low` for the "field" and `surface_container_lowest` for the "players" (the cards).

### Don't:
*   **Don't use 1px lines:** They make the app feel like a legacy spreadsheet. Use color shifts.
*   **Don't use generic grey shadows:** They deaden the vibrant SSG Red. Always tint your shadows.
*   **Don't over-round:** Stick to the `DEFAULT` (8px) roundness. Going to "full" roundness on buttons kills the "Strong/Precision" vibe of the Landers brand.