# Design System Document

## 1. Overview & Creative North Star
### The Athletic Editorial
This design system is built to move beyond the "standard app" aesthetic and into the realm of high-performance digital journalism. Our Creative North Star is **"The Athletic Editorial"**—a visual language that treats every screen like a premium sports broadsheet optimized for the modern athlete. 

We reject the rigid, centered symmetry of generic templates. Instead, we embrace **intentional asymmetry**, high-contrast typography scales, and overlapping elements that evoke a sense of forward motion and velocity. This system is designed to feel authoritative, fast, and bespoke, capturing the spirit of the Lotte Giants through a sophisticated, layered interface.

---

## 2. Colors
Our palette is rooted in the heritage of the Lotte Giants, reimagined through Material Design tokens to provide depth and tonal hierarchy.

*   **Primary (Lotte Red):** `primary` (#a9001d) and `primary_container` (#d11b2e). Use these for high-action touchpoints and hero highlights.
*   **Secondary (Dark Navy):** `on_secondary_fixed` (#001b3c). This provides the "weight" of the system, used for headers and foundational backgrounds to ground the vibrant red.
*   **Tertiary (Sky Blue):** `tertiary_fixed` (#c1e8ff) and `tertiary_fixed_dim` (#95ceee). Use sparingly for data visualizations or secondary accents to provide a "breath" of light against the heavy navy.

### The "No-Line" Rule
**Explicit Instruction:** Prohibit the use of 1px solid borders to define sections. Layout boundaries must be defined solely through:
1.  **Background Color Shifts:** Placing a `surface_container_low` card atop a `surface` background.
2.  **Tonal Transitions:** Using the spacing scale to create clear air between distinct content blocks.

### The Glass & Gradient Rule
To achieve a premium, custom feel:
*   **Signature Gradients:** For primary CTAs and hero backgrounds, use a subtle linear gradient transitioning from `primary` (#a9001d) at the top-left to `primary_container` (#d11b2e) at the bottom-right.
*   **Glassmorphism:** For floating overlays (e.g., player stats on top of imagery), use `surface_container_lowest` with a 70% opacity and a 20px backdrop-blur to allow brand colors to bleed through.

---

## 3. Typography
We utilize a dual-font strategy to balance technical precision with editorial impact.

*   **Display & Headlines (Manrope):** These are your "shouting" levels. Use `display-lg` (3.5rem) and `headline-lg` (2rem) for player names, scores, and breaking news. The geometric nature of Manrope feels high-performance and technical.
*   **Body & Titles (Inter):** For density and legibility. `body-md` (0.875rem) is our workhorse for news snippets and statistics.
*   **Hierarchy as Identity:** Create a "Brutalist Editorial" look by pairing a massive `display-sm` headline with a tiny, uppercase `label-sm` sub-header. This extreme contrast is the hallmark of premium design.

---

## 4. Elevation & Depth
Depth in this system is not about "lifting" objects off the page; it’s about **Tonal Layering**.

### The Layering Principle
Think of the UI as stacked sheets of fine material.
*   **Base:** `surface` (#f7f9fc)
*   **Nested Elements:** Place a `surface_container_lowest` card (Pure White) on a `surface_container_low` section to create a soft, natural lift.

### Ambient Shadows
When a "floating" effect is necessary for a high-priority action:
*   Use extra-diffused shadows (Blur: 24px-32px).
*   **Opacity:** 4%–6%.
*   **Color Tint:** Instead of grey, use a shadow tinted with `on_secondary_fixed` (#001b3c) to keep the depth feeling integrated into the brand palette.

### The "Ghost Border" Fallback
If a container requires more definition for accessibility, use a **Ghost Border**:
*   **Token:** `outline_variant` (#e5bdbb)
*   **Opacity:** 15%.
*   **Rule:** Never use 100% opaque borders.

---

## 5. Components

### Cards & Lists
*   **Rounding:** All cards must use `md` rounding (0.75rem / 12px) to match the user's signature request.
*   **No Dividers:** Forbid the use of horizontal rules. Separate list items using `surface_container` shifts or `3` (1rem) spacing gaps.
*   **Editorial Layout:** Text inside cards should be left-aligned with ample `4` (1.4rem) padding to maintain a dashboard feel.

### Buttons
*   **Primary:** High-performance pill shape (`full` rounding). Use the Signature Gradient.
*   **Secondary:** `on_secondary_container` background with `on_secondary` text.
*   **Padding:** Vertical `2.5` (0.85rem), Horizontal `5` (1.7rem).

### Performance Chips
*   Used for player positions or game status.
*   Style: `surface_container_highest` background with `on_surface_variant` text.
*   Shape: `sm` rounding (0.25rem) for a more technical, "tag" aesthetic.

### Sports-Specific Modules (Additional)
*   **The "Stat Sheet":** A glassmorphic overlay using `tertiary_container` at 20% opacity for real-time player performance metrics.
*   **The "Scoreboard Hero":** A full-width `on_secondary_fixed` (Dark Navy) container using `headline-lg` for scores, with a `primary` (Red) vertical accent bar on the left edge.

---

## 6. Do's and Don'ts

### Do
*   **Do** use intentional white space (Spacing `8` or `10`) to separate major editorial sections.
*   **Do** use asymmetrical imagery (cropping a player so they bleed off the edge of a card) to create energy.
*   **Do** prioritize typographic scale over color to show importance.

### Don't
*   **Don't** use 1px solid dividers or high-contrast borders. It breaks the "premium editorial" flow.
*   **Don't** use standard iOS "System Blue" for links; use the `tertiary` Sky Blue.
*   **Don't** clutter the screen. If a piece of data isn't vital to the "Performance Dashboard" story, move it to a nested layer.
*   **Don't** use centered text for body copy. Keep it strictly left-aligned for an authoritative, structured look.