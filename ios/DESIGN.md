# KickBAC design

The approved Home screen is the visual reference for the main app. Preserve its plain dark background, rounded system type, open spacing, readable values, and restrained Liquid Glass. The white onboarding pages stay plain white.

## Layout and type

- Use `SplashBackground` for the main canvas. Keep screens dark.
- Match Home's 24-point horizontal margins and quiet header.
- Give each screen one clear focal point. Home and Me have no page title at the top. On Me, keep the 148-point profile photo at the top left, with the name beside its bottom-right edge. Edit profile is an icon button beside settings at the top right. Stack the name below the photo at accessibility text sizes.
- Me has one Settings entry point: the top-right icon. Saved readings and Last check both open reading history when tapped; their whole statistic area is tappable. There is no separate Reading history or Settings row below the statistics.
- Games played, Wins, and Points open Recent games. Use left-aligned party headings above game rows with square game images, outcome, awarded points, and the linked breathalyzer check-in. Show unavailable associations honestly until the backend supplies them; never group games into invented parties or guess a check-in from its time.
- Center Points on its own full-width row beneath the other profile statistics.
- Settings contains camera permissions, account actions, and version. Profile editing belongs on Me. Omit the permission explanation, refresh action, and successful-load messages. Account actions are Sign out and Delete account; never report deletion until the backend confirms it.
- Use rounded system type. Large values use medium weight and monospaced digits; small labels use secondary emphasis.
- Let spacing group information. Keep simple statistics open on the background rather than putting every value inside a card.
- Adapt for Dynamic Type. Profile content can scroll; Home's normal layout stays fixed.

## Glass and color

- Use native glass for buttons, navigation, and action surfaces. Keep data and text clear.
- Put related glass controls in a `GlassEffectContainer`, with spacing matching their layout.
- Keep colors soft beneath glass, with enough saturation to remain distinct. Use color when it communicates content or state.
- The Home arc needs a broad color backdrop and restrained glass opacity. Full-strength refraction on a narrow colored arc erases its colors. Clip the combined result to its open-bottom shape.
- Keep progress fill above the material so it stays visible.
- Respect Reduce Transparency, Increase Contrast, and Reduce Motion.

## Profiles and controls

- Profile photos are squares with softly rounded corners, never circles. Use the existing camera and square crop.
- Profile photos can be retaken, but the editor has no Remove photo action. Omit the party-name helper sentence; keep name validation errors.
- Camera preview fills the largest square that fits in the available space. Show the full saved crop, without an inset guide or outer dimming.
- Glass can frame a photo; the image itself stays sharp.
- Prefer native capsule buttons and circular toolbar controls, with touch targets of at least 44 points.
- Use the supplied icons and assets. Preserve the Mogi wordmark style. Use `KickBAC` for all user-facing names, including app display name, Welcome, launch, permissions, errors, and accessibility labels. Welcome and launch share the `KickBACWordmark` asset.
- Show real account data. Never turn Home demo readings into saved history or invent game statistics.

## Copy and motion

- Preserve wording the user already likes. Keep new copy short and natural, using Better Writing and Humanizer.
- Use Apple Design and Emil Design Engineering for interface decisions. Use native SwiftUI before adding custom machinery.
- Give immediate press feedback. Keep occasional state transitions around 150 to 250 ms, without decorative looping motion.
- Retain existing auth, camera, history, and account behavior while polishing the interface.
- Hide Cancel while a breath sample is running. Device tests may be cancelled while armed and waiting, before sampling starts.

## Verification

Build with Xcode-beta and use code checks appropriate to the change. Do not use vision or Device Hub unless the user explicitly asks to use them again. A successful build alone does not verify rendering; report that limit accurately.

Debug builds accept `--show-profile` to open Me directly. This changes only the initial selected tab and does not bypass sign-in or supply account data.

Report installation accurately when installing on the connected iPhone. Commit, push, or merge only with explicit permission.
