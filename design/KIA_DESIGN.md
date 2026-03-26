# Design System Document: Kinetic Precision

## 1. Overview & Creative North Star
**Creative North Star: "The Kinetic Stadium"**
This design system is built to mirror the visceral energy of professional baseball—the tension of the mound, the speed of the pitch, and the high-performance engineering of modern sports equipment. We are moving beyond a "generic sports app" look to create a high-end editorial experience that feels both aggressive and meticulously disciplined.

To break the "template" look, this system utilizes **intentional asymmetry** and **tonal depth**. We favor massive, high-contrast typography scales juxtaposed with generous negative space. Elements should feel like they are floating in a dark, atmospheric environment, using light not as a border, but as a medium to define volume and importance.

## 2. Colors
Our palette is anchored in the KIA Tigers' legacy: power, precision, and passion. We utilize a sophisticated dark-mode architecture to ensure data remains the hero.

### Color Tokens
- **Primary (Red):** `#E51937` (`primary_container`). This is our "heartbeat" color. Use it sparingly for high-impact actions and critical highlights.
- **Surface (Black/Navy):** `#061520` (`surface`). The foundational "darkness" of the stadium.
- **Neutral (White/Silver):** `#d5e4f4` (`on_surface`). High-legibility contrast for data and narrative.

### The "No-Line" Rule
**Prohibit 1px solid borders for sectioning.** Boundaries must be defined solely through background color shifts or subtle tonal transitions.
- Use `surface_container_low` for secondary sections.
- Use `surface_container_high` for interactive elements.
- By shifting the background color, we create a seamless, sophisticated flow that feels "carved" rather than "outlined."

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. 
- **Layer 0:** `surface` (The deep background).
- **Layer 1:** `surface_container_low` (Main content blocks).
- **Layer 2:** `surface_container` (Nested cards or list items).
- **Layer 3:** `surface_container_highest` (Floating elements and modals).

### The "Glass & Gradient" Rule
To add visual "soul," avoid flat red buttons. Use subtle linear gradients from `primary` to `primary_container` (angled at 135°) to simulate light hitting a curved surface. For floating headers or navigation bars, use **Glassmorphism**: semi-transparent `surface_variant` with a 16px-24px backdrop blur to allow the team's energy to bleed through the interface.

## 3. Typography
We use **Inter** as our sole typeface, relying on extreme weight and scale variations to drive the editorial narrative.

- **Display (The "Scoreboard" Scale):** `display-lg` (3.5rem) and `display-md` (2.75rem). Use these for player numbers, scores, and hero headlines. Tighten letter-spacing (-0.04em) for an aggressive, high-performance look.
- **Headlines & Titles:** Use `headline-lg` (2rem) for section headers. Ensure high contrast against the background to maintain an authoritative tone.
- **Labels:** `label-md` (0.75rem). Use uppercase with increased letter-spacing (0.1em) for technical data points (e.g., ERA, WHIP, EXIT VELO) to give them a premium, instrument-panel feel.

## 4. Elevation & Depth
In this system, depth is achieved through **Tonal Layering** rather than structural lines.

- **The Layering Principle:** Place a `surface_container_low` card on a `surface` background to create a soft, natural lift. The depth comes from the light emission of the surface itself.
- **Ambient Shadows:** When a "floating" effect is required (e.g., a FAB or a modal), use extra-diffused shadows.
    - **Shadow Color:** A tinted version of `on_surface` at 6% opacity.
    - **Blur:** 24px to 48px. 
    - This mimics the ambient stadium lighting rather than a harsh, artificial drop shadow.
- **The "Ghost Border" Fallback:** If a border is essential for accessibility, use the `outline_variant` token at **15% opacity**. Never use 100% opaque borders; they disrupt the "Kinetic Stadium" flow.

## 5. Components

### Buttons
- **Primary:** Rounded `ROUND_EIGHT` (0.5rem). Background: `primary_container` with a subtle top-down gradient. Text: `on_primary_container` (white), bold.
- **Tertiary:** No background. Text: `primary`. On hover, use a `surface_container_highest` background shift.

### Sports Data Chips
- **Status Chips:** Use `secondary_container` for neutral stats and `primary_container` for "Live" or "Hot" stats.
- **Design:** No borders. Use `ROUND_EIGHT` corners and `label-sm` typography.

### Input Fields
- **Architecture:** Background should be `surface_container_lowest`. 
- **Active State:** Instead of a thick border, use a 2px bottom-bar in `primary` (Red) and a subtle inner-glow.

### Cards & Lists
- **Forbid Divider Lines:** Separate list items using the `Spacing Scale`. 
- Use a `spacing-4` (1rem) gap between items. 
- Use a slight color shift to `surface_container_low` on hover to define the interactive area.

### Glass Tooltips
- Floating tooltips must use the Glassmorphism rule (semi-transparent `surface` with backdrop blur) to maintain the feeling of depth and high-end technicality.

## 6. Do's and Don'ts

### Do:
- **Use Asymmetry:** Place large display type off-center to create a sense of motion.
- **Embrace the Dark:** Keep 90% of the UI in the `surface` and `surface_container` range to make the Red and White accents pop with "aggressive" intent.
- **Scale for Impact:** Use `display-lg` for single statistics to create an editorial, magazine-style layout.

### Don't:
- **Don't use 1px borders:** It makes the UI look like a generic dashboard. Use color blocks instead.
- **Don't use pure grey shadows:** Always tint shadows with the background hue to maintain the deep navy-black atmosphere.
- **Don't clutter:** Sports data can be overwhelming. Use the `Spacing Scale` (specifically `spacing-8` and `spacing-12`) to let the data "breathe."
- **Don't use standard "Alert Blue":** For informational states, use the `tertiary` (#76d4e4) "Cyan" to maintain the modern, technical sports aesthetic.