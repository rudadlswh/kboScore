# Design System Document

## 1. Overview & Creative North Star: "The Arcane Arena"
This design system is built to transform a standard sports dashboard into a high-performance, mystical digital environment specifically for the KT Wiz faithful. We move away from the "flat grid" of traditional sports apps and toward **The Arcane Arena**—a philosophy that treats the UI as a layered, high-tech command center. 

The aesthetic is driven by high-contrast editorial typography, intentional asymmetry, and "Magic Black" depth. We break the template look by using overlapping elements (e.g., player imagery breaking the bounds of containers) and sharp, aggressive geometric shapes that mirror the KT Wiz crest. This is not just a data display; it is a premium, immersive experience that feels as fast and sharp as a 100mph fastball.

---

## 2. Colors
Our palette is rooted in the KT Wiz identity, re-engineered for digital depth and visual hierarchy.

### The Palette (Material Design Tokens)
*   **Primary (Victorious Red):** `#ffb4ab` (Surface), `#EC1C24` (Brand Core). Used for critical actions, live scores, and high-energy moments.
*   **Secondary (Cool Grey):** `#bec8ce`. Provides a sophisticated, metallic contrast to the deep blacks.
*   **Background (Magic Black):** `#131313`. A deep, ink-like canvas that allows red and grey to pop with high intensity.

### The "No-Line" Rule
To maintain a high-end editorial feel, **1px solid borders are strictly prohibited** for sectioning. We define space through:
1.  **Background Shifts:** Placing a `surface-container-low` component against a `surface` background.
2.  **Tonal Transitions:** Using color blocking rather than lines to separate content streams.

### Surface Hierarchy & Nesting
Think of the UI as physical layers. Use the surface-container tiers to create depth:
*   **Lowest Layer:** `surface-container-lowest` (#0e0e0e) for the deep background.
*   **Mid-Level:** `surface-container` (#201f1f) for main content cards.
*   **Top-Level:** `surface-container-highest` (#353534) for active elements or "hover" states.

### Glassmorphism & Signature Textures
For floating elements (modals, score overlays), use a "Frosted Magic" effect: 
*   Apply `surface_variant` at 60% opacity with a 20px Backdrop Blur.
*   Use a subtle gradient from `primary` (#EC1C24) to `primary_container` (#ff544b) on CTAs to give them a "glowing" soul that flat color cannot replicate.

---

## 3. Typography
The typography system uses a dual-font strategy to balance aggressive sports energy with modern readability.

*   **Display & Headlines (Space Grotesk):** This is our "Aggressive" weight. Used for scores, player names, and big statistical moments. It feels sharp, modern, and high-performance.
*   **Body & Titles (Inter):** Our workhorse. It provides a clean, neutral balance to the expressive headlines.

**Scale Highlights:**
*   **Display-LG (3.5rem):** Reserved for live game scores. Always Bold/Black weight.
*   **Headline-MD (1.75rem):** For section headers (e.g., "League Standings").
*   **Label-SM (0.6875rem):** For metadata (e.g., "Innings," "Pitch Count"). Use All-Caps with 0.05em tracking for a premium feel.

---

## 4. Elevation & Depth
In this system, depth is a tool for focus, not just decoration.

### The Layering Principle
Avoid "drop shadows" on every box. Instead, stack the surface tokens. A card using `surface-container-low` sitting on a `surface` background creates a natural, soft lift.

### Ambient Shadows
When an element must "float" (like a FAB or a floating scoreboard), use an **Ambient Shadow**:
*   **Color:** `#000000` at 8% opacity.
*   **Blur:** 24px - 40px (Extra-diffused).
*   This mimics the soft, natural light of a stadium at night.

### The "Ghost Border" Fallback
If an element lacks contrast against its background, use a **Ghost Border**:
*   Token: `outline-variant` (#5e3f3c).
*   Opacity: 15%.
*   This provides a hint of structure without the "boxiness" of a standard UI.

---

## 5. Components

### Buttons
*   **Primary:** Solid `Victorious Red` with a 2px inner glow. No border. `xl` (0.75rem) rounded corners.
*   **Secondary:** Glassmorphic background (30% opacity `Cool Grey`) with `on_surface` text.
*   **Interaction:** On hover, the primary button should slightly expand (scale: 1.02) and increase its "glow" (shadow spread).

### Cards & Lists
*   **Rule:** **No Divider Lines.** Separate list items using the spacing scale (e.g., `spacing-4` / 0.9rem) or by alternating background tones slightly between `surface-container-low` and `surface-container-medium`.
*   **KT Wiz Special:** Cards should feature an "asymmetric" corner—keep the 8px (`lg`) radius on three corners, but consider a 0px "sharp" corner on the top-right to mimic the KT Wiz "W" crest.

### Inputs & Fields
*   **Styling:** Use `surface_container_highest` for the input track. Use a `Victorious Red` 2px bottom-bar only when the field is focused.
*   **Error State:** Use `error` (#ffb4ab) for text and icon, never a full red box.

### Signature Component: The "Magic Scoreboard"
A floating glassmorphic container at the top of the dashboard. Use `Space Grotesk` at `Display-MD` for scores. Background: 40% `Magic Black` with high backdrop blur and a `Victorious Red` top-edge accent.

---

## 6. Do’s and Don’ts

### Do:
*   **Do** use extreme white space (Spacing 16 or 20) to separate major sections.
*   **Do** let player photography overlap containers to create a 3D, "high-end editorial" depth.
*   **Do** use `Victorious Red` sparingly for "Live" status and primary actions—treat it like a laser, not a paint bucket.

### Don’t:
*   **Don’t** use 1px solid black or grey lines to separate content.
*   **Don’t** use standard "system" shadows. They feel cheap; use our Ambient Shadows.
*   **Don’t** use rounded corners larger than 8px (`lg`) unless it's a pill-shaped chip or button. We want the app to feel "sharp" and "aggressive," not "bubbly."
*   **Don't** use high-contrast white text on pure black. Use `on_surface` (#e5e2e1) to reduce eye strain and maintain a premium, matte look.