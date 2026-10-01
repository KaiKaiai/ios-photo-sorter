# Sort: design guide

The look is **minimal, clean and modern**: it should feel like a first-party Apple app. Photos are the content, and the interface stays quiet around them. Change this guide only on purpose. When adding UI, reuse what's here before inventing anything new.

## Principles

1. **Content first.** Photos and videos take the space. Controls are small, sit at the edges, and use system materials, not heavy fills.
2. **Native over custom.** Use stock SwiftUI controls, `NavigationStack`, toolbars, alerts, confirmation dialogs and sheets. Don't redraw what iOS already provides.
3. **One clear action per screen.** Each screen has at most one prominent (filled) button, and everything else is bordered or plain.
4. **Quiet until touched.** No decoration, gradients, drop shadows on cards, or ornamental animation. Motion and haptics appear only in response to the owner.
5. **Calm about destruction.** Destructive actions are red, confirmed, and say plainly what happens to the photos.

## Colour

- Use **system semantic colours only**, so light and dark mode work automatically:
  - `Color(.systemBackground)` for screens.
  - `Color(.secondarySystemBackground)` for panels such as the sidebar.
  - `Color(.tertiarySystemFill)` for image placeholders.
  - `.primary` and `.secondary` for text.
- The accent is the system tint, `Color.accentColor`, used for selection and primary actions.
- Colours with fixed meanings:
  - **Red:** delete, Trash and destructive actions only.
  - **Green:** keep and success only.
- Never use hex colours, custom palettes, or text colours that ignore dark mode. Overlays on photos may use white with a soft shadow for legibility.

## Typography

- System font, Dynamic Type text styles only: `.title`, `.title2`, `.title3`, `.headline`, `.body`, `.subheadline`, `.footnote`, `.caption`, `.caption2`.
- Use weight for hierarchy (`.semibold` for headings and primary buttons, `.medium` for labels), never size alone.
- Big numbers, like the "items left" count, use `.system(size:weight: .bold, design: .rounded)` with `.monospacedDigit()` and `.contentTransition(.numericText())`.
- Write labels in sentence case and keep them short. Use no full stops on single-line labels.

## Shape and spacing

| Token | Value | Used for |
|---|---|---|
| Card corner radius | 20 | Sorting cards and large surfaces |
| Tile corner radius | 14 | Album covers in grids |
| Small corner radius | 12 / 8 | Sidebar tiles and thumbnails |
| Screen padding | 16–24 | Outer padding: 16 for dense grids, 24 for sparse screens |
| Stack spacing | 4 / 6 / 12 / 14 / 18 / 28 | Tight label pairs, tiles, grid gutters and section gaps |

- Always use `RoundedRectangle(cornerRadius:style: .continuous)` for Apple-style corners.
- Grids use `GridItem(.adaptive(minimum:maximum:))`, so they adapt to every iPhone width.
- Respect safe areas. Put bottom action bars in `.safeAreaInset(edge: .bottom)` on a `.bar` material.

## Icons

- Use SF Symbols only, matched to Apple's meanings: `trash`, `plus`, `pencil`, `gearshape`, `checkmark.circle.fill`, `rectangle.stack`.
- Use filled variants for an active or selected state (`trash.fill` when the Trash has items, `checkmark.circle.fill` when selected).
- Give every button that's only an icon an `accessibilityLabel`.

## Buttons

| Role | Style |
|---|---|
| The screen's main action (Start) | `.borderedProminent`, `.controlSize(.large)`, full width |
| Secondary actions (Trash, Albums) | `.bordered` |
| Destructive main action (Delete N) | `.borderedProminent` with `.tint(.red)`, behind a confirmation |
| Toolbar actions | Plain text ("Select", "Cancel") or a single SF Symbol (`plus`) |

## Motion

- Use springs, short and settled: `.spring(response: 0.3–0.35, dampingFraction: 0.8–0.86)` for cards, and `.snappy` for selection and mode changes.
- Animate state changes with `withAnimation`, not by hand. Use `.transition(.scale.combined(with: .opacity))` for small badges.
- Never block input with animation. A new gesture finishes the previous animation at once.

## Haptics

Use the helpers in `Haptics` (in `Device.swift`):

- `Haptics.tap()`: a light tick for every routine action (swipe, file, toggle a selection).
- `Haptics.bump()`: entering a mode, such as holding to start selecting.
- `Haptics.done()`: a completed or destructive action succeeded (deleted, created).

Don't add haptics to scrolling or passive updates.

## Patterns

- **Selection mode:** holding an item, or tapping **Select** in the toolbar, enters it.
  - The title shows "N Selected", and Cancel replaces Back.
  - **Select All** / **Deselect All** goes at the top right.
  - Selected items show a `checkmark.circle.fill` badge, an accent outline and a slight scale-down.
  - The batch action sits in a bottom bar.
- **Creating and renaming:** use an `.alert` with one `TextField`. Disable the confirm button while the name is blank.
- **Per-item menu:** tap an item to open a `.confirmationDialog` titled with its name, with the destructive option last.
- **Empty states:** a large secondary SF Symbol, a one-line title, and at most one button.
- **Errors:** use `.libraryErrorAlert()` with plain-English messages. Never show raw error codes on their own.
