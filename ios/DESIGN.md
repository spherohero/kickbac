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
- Custom icons must come from the selected Figma Hi-fi icons, with their original paths, or artwork the user explicitly supplies or commissions. Do not substitute SF Symbols. Party uses the approved NFC, Chevron right, Plus, Question, Pencil, and Settings assets. Its tap illustration also uses Liam's supplied phone SVG and the breathalyzer silhouette he requested from his enclosure reference.
- Show real account data. Never turn Home demo readings into saved history or invent game statistics.

## Copy and motion

- Preserve wording the user already likes. Keep new copy short and natural, using Better Writing and Humanizer.
- Use Apple Design and Emil Design Engineering for interface decisions. Use native SwiftUI before adding custom machinery.
- Give immediate press feedback. Keep occasional state transitions around 150 to 250 ms, without decorative looping motion.
- Retain existing auth, camera, history, and account behavior while polishing the interface.
- Hide Cancel while a breath sample is running. Device tests may be cancelled while armed and waiting, before sampling starts.

## Party preview

- Party starts with tap-to-join, a code fallback, and Create a party. Creating asks for the party name and illustrates tapping to bind the breathalyzer. Do not expose device IDs, a manual device picker, or device-selection helper text on Create party or the room header.
- The host chooses games. Use matching compact colored cards inspired by the supplied Games reference, with KickBAC's rounded system type. Trivia is warm yellow; Pictionary is lavender. Cards use a 164-point minimum height that grows with text, 24-point padding, 28-point corners, and matching 64-point approved game illustrations. Use the final full-color Hi-fi SVG artwork from Trivia `191:235` and Pictionary `191:245`, omitting only the colored rounded-square backing in the app assets. Preserve the paper outlines, pencil, question mark, accent positions, and original rendering without tint or extra icon padding. Use transparent illustrations on the colored cards and game details. Ongoing-game and profile Recent games rows use the same approved artwork on a rounded-square fill drawn from the exact shared card color; never substitute a gradient or a different tint. On game cards, offset the artwork 8 points right and 8 points up to align the foreground with the title. Give card backgrounds an upward black shadow (26% opacity, 4-point radius, y −4) so the front Pictionary card casts a visible seam onto Trivia. Keep Pictionary above Trivia in drawing order. Group title and description with 8-point spacing; omit category labels and their footer chevron. Overlap cards by 56 points so the next card covers the preceding card’s lower curves. A card with another overlapping it reserves a 68-point bottom inset, keeping 12 points clear below growing content. Separate cards by 16 points at accessibility sizes. Never obscure text or artwork to create the stack.
- The game picker uses 24-point horizontal margins, a 12-point top inset, and 20 points between Choose a game and the cards. Keep the flat SplashBackground, native navigation, and a Close action for the sheet; pushed game details use native Back navigation. Preserve useful whitespace instead of adding filler, statistics, or extra explanatory copy.
- Guests see ongoing games, the leaderboard, and people. Omit the ongoing-games section when there are none. Keep leaderboard and people open on the dark canvas.
- Native glass belongs on controls; game cards are colored content surfaces. Profile photos remain softly rounded squares.
- Party remains an ephemeral UI preview. Omit the Party preview banner/icon, welcome heading/subtitle, and development explanations from entry, create, people, picker, and game details. Use Create party, Start a game, and Start game for the actions. Keep Preview as inside the options menu; its trigger matches Me's circular Settings icon and has no Host label. The KICK26 code, tap action, selected breathalyzer, and ongoing game remain illustrative only. Show only the current profile and no invented scores.
- Align the party name and Settings-style options button in the same header row, without a star beside the name. Keep device IDs hidden. The code-joined sample is named Party, without a preview suffix.
- Join sheets keep the code field and Join with code action, without You're invited, a standalone NFC icon, tap instructions, or the Join party action. Tap entry shows the shared phone-to-breathalyzer illustration above the code form.
- Use exactly Tap your phone to the breathalyzer as a plain caption beside every tap animation, including Create. Create uses the exact shared illustration/caption as Join; the instruction is not a button and never changes to an NFC icon. No simulated tap selection is required before local creation; require only a valid party name. Do not claim a live NFC connection. Create starts at Party name, without Make it your party.
- Invite people shows the animation and Tap your phone to the breathalyzer, then Or enter code to join above the horizontally centered party code. Omit invitation headings and preview disclaimers.
- The tap illustration uses monochrome filled silhouettes. Stylize the breathalyzer with a smooth rounded body, a rounded left mouthpiece, and no mounting nubs or invented controls. The NFC mark should be large and readable. Loop the approach/hold/withdraw sequence while the scene is active; Reduce Motion shows a static contact pose. The artwork is clipped to its area and ignores touches so inputs remain available.
- Live party creation, device binding, NFC/code joining, membership, role permissions, party scores, and gameplay remain separate work. Party joining must not arm a breath test or expose private readings.

## Verification

Build with Xcode-beta and use code checks appropriate to the change. Do not use vision or Device Hub unless the user explicitly asks to use them again. A successful build alone does not verify rendering; report that limit accurately.

Debug builds accept `--show-profile` to open Me directly. This changes only the initial selected tab and does not bypass sign-in or supply account data.

Report installation accurately when installing on the connected iPhone. Commit, push, or merge only with explicit permission.
