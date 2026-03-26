# Design System Document: The Digital Stadium Experience

## 1. Overview & Creative North Star
### The Creative North Star: "The Digital Arena"
This design system is not a mere utility app; it is a premium extension of the LG Twins stadium experience. We move away from the "flat, boxed" aesthetic of standard sports apps toward a **high-performance editorial layout**. 

The "Digital Arena" philosophy centers on high-velocity visuals, aggressive typography scales, and a sense of physical atmosphere. By using intentional asymmetry (mimicking the dynamic angles of the LG Twins logo) and overlapping elements, we create a UI that feels like it’s in motion. We reject generic grids in favor of depth, tonal layering, and sophisticated silver accents that mirror the metallic sheen of professional sports equipment.

---

## 2. Colors: High-Contrast Performance
The palette is rooted in the aggressive Red and Black of the LG Twins, balanced by metallic silvers for a "Sleek Tech" feel.

### Core Palette
- **Primary High-Performance Red (`#A50034` / `primary_container`):** Reserved for high-action CTAs, live game indicators, and victory states.
- **Deep Stadium Black (`#131313` / `surface`):** The foundation of our dark mode. It provides the "void" that allows colors to pop.
- **Silver/Gray Accents (`#C6C6C6` / `tertiary`):** Used to represent precision—scorelines, timing data, and secondary technical information.

### The "No-Line" Rule
To maintain a high-end feel, **1px solid borders are prohibited** for sectioning. We define boundaries exclusively through:
1.  **Tonal Transitions:** Moving from `surface_container_low` to `surface_container`.
2.  **Negative Space:** Utilizing the `Spacing Scale (8, 10, 12)` to create breathing room between content blocks.
3.  **Physical Stacking:** Using background color shifts to indicate nested content.

### Glass & Gradient Rule
For floating player cards or navigation bars, utilize **Glassmorphism**. Use `surface_container` at 80% opacity with a `20px` backdrop-blur. 
Main CTAs should use a subtle linear gradient: `primary` (#FFB2B8) to `primary_container` (#A50034) at a 135-degree angle to provide a "signature" glow.

---

## 3. Typography: The Editorial Edge
We use two typefaces to balance aggressive sports energy with readable data.

- **Display & Headlines (Lexend):** A wide, geometric sans-serif that mimics the bold "TWINS" wordmark. 
    - *Usage:* Player names, scores, and section headers. 
    - *Intent:* Large scales (`display-lg` at 3.5rem) create an editorial, magazine-like hierarchy.
- **Body & Labels (Inter):** High-legibility grotesque for technical stats and news.
    - *Usage:* Player bios, box scores, and settings.
    - *Intent:* Provides a "technical data" feel that contrasts against the bold Lexend headlines.

---

## 4. Elevation & Depth: Tonal Layering
We do not use shadows to create "pop"; we use **Light and Material Logic**.

- **The Layering Principle:** 
    - Base: `surface` (#131313)
    - Section: `surface_container_low` (#1C1B1B)
    - Card: `surface_container` (#201F1F)
    - Active State: `surface_container_high` (#2A2A2A)
- **Ambient Shadows:** When a card *must* float (e.g., a modal or notification), use an extra-diffused shadow: `offset-y: 24px, blur: 48px, color: rgba(0, 0, 0, 0.4)`.
- **The "Ghost Border":** If accessibility requires a border, use `outline_variant` at **15% opacity**. Never use 100% opaque lines.
- **Glassmorphism:** To mimic the stadium's VIP suites and high-tech displays, use `surface_variant` with a 10% opacity and a heavy blur for background overlays.

---

## 5. Components

### Buttons
- **Primary:** Lexend Bold, All-Caps. Gradient fill (`primary_container` to `primary`). `rounded-md` (0.375rem).
- **Secondary:** Silver-tone (`tertiary_container`). Ghost-border (15% opacity) for an "industrial" look.
- **Floating Action Button (FAB):** Strictly Deep Red (#A50034) with a high-glow `primary` shadow.

### Cards & Lists
- **Forbid dividers.** Use `Spacing Scale 4` (0.9rem) to separate list items. 
- **Player Cards:** Feature an asymmetrical layout where the player image overlaps the card's top edge (the "Breaking the Grid" technique).
- **Scorecards:** Use `surface_container_highest` for the team in possession to provide a subtle "active" highlight.

### Status Indicators
- **Live State:** A pulsing `primary_container` (#A50034) dot with a 50% opacity ring around it.
- **Win/Loss:** Silver for neutral, Deep Red for LG Twins wins. No green; we stay true to the brand palette.

### Input Fields
- Use `surface_container_lowest` for the field background. 
- Focus state is indicated by a 2px `primary` underline rather than a full box stroke.

---

## 6. Do's and Don'ts

### Do:
- **Use Large Typography:** Let `display-lg` headlines bleed near the edge of the screen for an editorial feel.
- **Embrace the Dark:** Treat the Dark Mode as the primary experience; Light Mode should feel like a "High-Contrast Technical" version using `surface_bright`.
- **Use Silver for Logic:** Use the `tertiary` silver tones for secondary stats (e.g., ERA, Batting Average) to keep the Red focused on "Action."

### Don't:
- **Don't use 1px Dividers:** They clutter the "Digital Stadium" aesthetic. Use background shifts instead.
- **Don't use Standard Shadows:** Avoid small, muddy drop-shadows. Stick to Tonal Layering.
- **Don't Round Everything:** Use `rounded-md` (0.375rem) or `rounded-none`. Avoid full circles for cards; we want the UI to feel sharp and high-performance, not "soft."
- **Don't use Generic Red:** Always refer to the `primary_container` (#A50034) to ensure the LG Twins brand identity is never diluted.