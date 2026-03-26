# Design System Strategy: High-Performance Athletic Editorial

## 1. Overview & Creative North Star
The Creative North Star for this design system is **"The Kinetic Stadium."** 

We are not building a static news app; we are building a high-velocity, digital arena. This system captures the aggressive, high-contrast energy of the Hanwha Eagles by blending the precision of sports broadcasting with a premium editorial aesthetic. We move beyond generic mobile grids by using **intentional asymmetry**—such as bleeding player imagery off-canvas—and **tonal layering** to create a sense of three-dimensional depth. The goal is a "Live-Action" interface where every score, stat, and swipe feels as impactful as a home run.

---

## 2. Colors: High-Octane Contrast
The palette is built on a "Pitch Black" foundation to ensure the Hanwha Orange feels electric and readable.

- **Primary Energy:** `primary` (#ff915d) and `primary_container` (#ff7936) are reserved for "Active" states, live scores, and critical CTAs.
- **The "No-Line" Rule:** We do not use 1px borders to separate content. Sectioning is achieved through background shifts. Use `surface_container_low` (#131313) for the main feed and `surface_container` (#191919) for nested cards.
- **Surface Hierarchy:** Treat the UI as layers of dark glass. 
    - Base: `surface` (#0e0e0e)
    - Depth: `surface_container_highest` (#262626) for floating action elements.
- **Glass & Gradient Rule:** For hero sections and player cards, use a linear gradient from `primary` to `primary_dim` at a 45-degree angle. Floating navigation bars should use `surface_container` with a `backdrop-blur` of 20px and 80% opacity to maintain a "Glassmorphism" effect.

---

## 3. Typography: Editorial Authority
We utilize a dual-font strategy to balance aggressive sports energy with legible data.

- **Display & Headlines (Space Grotesk):** This is our "Voice." Large, wide, and unapologetic. Use `display-lg` (3.5rem) for score totals and `headline-lg` (2rem) for game-changing news. Its geometric nature reflects the modern, high-performance tech of sports analytics.
- **Body & Labels (Inter):** This is our "Information." Inter is used for technical stats, player rosters, and long-form articles. Its neutral character ensures high readability against the dark background. 
- **Hierarchy Tip:** Use `label-sm` (all-caps) with 0.1rem letter spacing for "Live" indicators or "In-Game" status to mimic professional broadcast overlays.

---

## 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are too "soft" for an aggressive sports brand. Instead, we use **Tonal Layering**.

- **The Layering Principle:** To lift a card, place a `surface_container_high` (#1f1f1f) element on a `surface_dim` (#0e0e0e) background. This creates a natural, sophisticated lift.
- **Ambient Shadows:** For high-priority floating elements (like a FAB), use a large 32px blur with only 6% opacity, using a tinted shadow derived from `primary_dim` to simulate the glow of a stadium floodlight.
- **The Ghost Border Fallback:** If a boundary is required for accessibility, use a 1px border using `outline_variant` (#484848) at **15% opacity**. It should be felt, not seen.
- **Kinetic Glass:** When modals appear, the background must blur (15px) to keep the user focused on the high-performance data in the foreground.

---

## 5. Components: Precision Engineered

### Buttons
- **Primary:** High-gloss `primary_container` with `on_primary_container` text. 12px (`DEFAULT`) corner radius.
- **Secondary:** Transparent background with a `Ghost Border`.
- **States:** On press, transition to `primary_fixed_dim` (#f96400) to provide haptic visual feedback.

### Scoreboard Chips
- Use `surface_container_highest` (#262626) with `primary` accents for the "Current Inning."
- **Forbid Dividers:** Do not use lines between scores. Use `Spacing 4` (0.9rem) to separate team names from point totals.

### Input Fields
- **Style:** Understated. Use `surface_container_low` with a 12px radius. 
- **Focus State:** Instead of a thick border, use a 2px bottom-only stroke of `primary` to suggest "forward motion."

### Dynamic List Items
- Separate news items using a background shift from `surface` to `surface_container_low`. 
- Incorporate a 4px vertical "accent bar" of `primary` on the far left of "Breaking News" items to draw immediate focus.

---

## 6. Do's and Don'ts

### Do:
- **Do** use `Spacing 16` (3.5rem) for top-level padding to create an "Editorial" breathing space.
- **Do** use large, aggressive player cutouts that overlap different surface containers to break the "boxed-in" feel.
- **Do** ensure all live score data uses `tertiary` (#f9f9f9) on dark surfaces for maximum contrast.

### Don't:
- **Don't** use 100% white (#ffffff) for long-form body text; use `on_surface_variant` (#ababab) to reduce eye strain on dark mode.
- **Don't** use standard 1px grey dividers. If you need separation, use a `2.5` (0.5rem) gap or a subtle background tier shift.
- **Don't** use rounded corners larger than 12px for primary containers; we want a "Modern iOS" feel, but too much roundness softens the "aggressive" team identity.