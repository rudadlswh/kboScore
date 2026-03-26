# Design System Document

## 1. Overview & Creative North Star: "The Digital Stadium"

This design system is engineered to capture the high-octane energy of professional baseball while maintaining the prestige of a historic winning tradition. Moving away from generic "sports app" templates, we adopt a **"Digital Stadium"** creative north star. This approach treats the UI not as a flat screen, but as a multi-dimensional environment defined by deep atmospheric layers, high-contrast editorial typography, and the sleek glass aesthetics of premium modern arenas.

The system breaks the mold of traditional grids through **Intentional Asymmetry**. We utilize overlapping elements—such as player portraits breaking the boundaries of cards or score displays that bleed into the background—to create a sense of forward motion. By blending the raw power of the "Bears" identity with a refined iOS-inspired card architecture, we create a high-performance experience that feels both historic and futuristic.

---

## 2. Colors & Surface Philosophy

Our palette is anchored in the legacy of the Doosan Bears: Deep Navy for authority, Bright Red for passion, and pure White for clarity.

### The "No-Line" Rule
To maintain a high-end, seamless feel, **1px solid borders are strictly prohibited** for sectioning content. Boundaries must be defined solely through:
*   **Background Shifts:** Transitioning from `surface` (#11102e) to `surface-container-low` (#191836).
*   **Tonal Transitions:** Using depth to separate information rather than structural wireframes.

### Surface Hierarchy & Nesting
We use Material 3 tonal tiers to create a "nested" physical environment. Treat the UI as stacked sheets of refined material:
*   **Base:** `surface` (#11102e) for the primary application background.
*   **Sections:** `surface-container` (#1d1c3a) for grouping major content blocks.
*   **Interactive Cards:** `surface-container-high` (#282745) or `surface-container-highest` (#323151) to pull key data (like live scores) toward the user.

### The "Glass & Gradient" Rule
For floating action menus or navigation bars, utilize **Glassmorphism**. Apply `surface-bright` (#373656) with a 60% opacity and a 20px backdrop-blur. This allows the vibrant navy and red tones of the content to bleed through, ensuring the UI feels integrated and high-performance. 

**Signature Texture:** CTAs should leverage a subtle linear gradient from `primary` (#ffb4ab) to `on-primary-container` (#f7262a) at a 135-degree angle to provide visual "soul" and depth.

---

## 3. Typography: Athletic Editorial

We pair two distinctive sans-serifs to balance technical performance with "The Bears" brand power.

*   **Display & Headlines (Space Grotesk):** This is our "Athletic" voice. Its geometric, slightly wider stance echoes stadium scoreboards. Use `display-lg` (3.5rem) for massive score updates and `headline-lg` (2rem) for game states.
*   **Body & Titles (Lexend):** Chosen for its exceptional readability in high-data environments. Lexend provides a clean, professional contrast to the expressive Space Grotesk headlines.
*   **Identity Through Scale:** Use extreme contrast. A `display-md` score paired immediately with a `label-sm` technical stat creates a sophisticated editorial hierarchy that feels intentional and premium.

---

## 4. Elevation & Depth: Tonal Layering

Traditional drop shadows are replaced by **Ambient Elevation** to mimic the soft, diffused lighting of a modern stadium lounge.

*   **The Layering Principle:** Place a `surface-container-lowest` (#0b0a28) card inside a `surface-container-low` (#191836) section to create a "recessed" effect for secondary data.
*   **Ambient Shadows:** For floating elements (Modals/FABs), use a multi-layered shadow: `0px 12px 32px rgba(11, 10, 40, 0.4)`. The shadow color must be a tinted version of the navy background, never pure black.
*   **The "Ghost Border" Fallback:** If a container requires more definition, use a "Ghost Border": the `outline-variant` (#47464d) at 15% opacity. This provides a tactile edge without breaking the "No-Line" rule.

---

## 5. Components

### Buttons
*   **Primary:** High-gloss Bright Red (`on-primary-container`) with white `title-sm` Lexend text. Corner radius: `md` (0.375rem).
*   **Secondary:** `surface-container-highest` background with a `ghost border`.
*   **Tertiary:** Text-only Lexend `label-md` in `primary-fixed-dim`.

### Cards & Lists
*   **Rule:** Forbid divider lines. Use `spacing-4` (1rem) of vertical white space or a shift to `surface-container-lowest` to separate list items.
*   **Scoreboard Cards:** Use `surface-container-high`, featuring `display-sm` Space Grotesk for team scores. Include a subtle `primary` (#ffb4ab) vertical accent bar (2px wide) on the left side of the winning team's row.

### Chips & Badges
*   **Status Chips:** (e.g., "LIVE", "FINAL") Use `inverse-primary` (#c00014) with white text. 
*   **Filter Chips:** Semi-transparent `secondary-container` (#454364) with `full` roundedness.

### Input Fields
*   Background: `surface-container-lowest`. 
*   Active State: Replace standard borders with a 2px bottom-accent in `primary`.

---

## 6. Do's and Don'ts

### Do
*   **Do** use asymmetrical margins. For example, give a headline more `spacing-8` on the left and `spacing-12` on the right to create "The Bears" powerful, forward-leaning energy.
*   **Do** use large-scale photography of players, allowing them to overlap card containers (`xl` radius: 0.75rem) to break the "boxed-in" feel.
*   **Do** ensure all interactive elements have a minimum touch target of 44x44pt, adhering to iOS standards.

### Don't
*   **Don't** use 100% opaque white for secondary text. Use `on-surface-variant` (#c8c5ce) to maintain visual hierarchy.
*   **Don't** use sharp 90-degree corners. Even the most "rugged" sports component should use at least the `DEFAULT` (0.25rem) radius for a modern feel.
*   **Don't** use standard grey shadows. Shadows must always be "tinted" with our Deep Navy to ensure they feel like part of the environment.