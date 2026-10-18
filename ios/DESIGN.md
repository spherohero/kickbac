# KickBAC design

The approved Home screen is the visual reference for the main app. Preserve its plain dark background, rounded system type, open spacing, readable values, and restrained Liquid Glass. The white onboarding pages stay plain white.

Scope the main app's dark appearance to its tabs. Let onboarding choose its own appearance so native birthday wheels use black text on the white form pages.

After restoring credentials, signed-out users always enter onboarding before the
main tabs, including after sign-out or session expiry. Keep onboarding active
through authentication and profile completion. Restored signed-in sessions keep
their existing profile completion check. Pending NFC links survive onboarding.

## Layout and type

- Use `SplashBackground` for the main canvas. Keep screens dark.
- Match Home's 24-point horizontal margins and quiet header.
- Give each screen one clear focal point. Home and Me have no page title at the top. On Me, keep the 148-point profile photo at the top left, with the name beside its bottom-right edge. Edit profile is an icon button beside settings at the top right. Stack the name below the photo at accessibility text sizes.
- Me has one Settings entry point: the top-right icon. Saved readings and Last check both open reading history when tapped; their whole statistic area is tappable. There is no separate Reading history or Settings row below the statistics.
- Games played, Wins, and Points open Recent games. Use left-aligned party headings above game rows with square game images, outcome, awarded points, and the linked breathalyzer check-in. Show unavailable associations honestly until the backend supplies them; never group games into invented parties or guess a check-in from its time.
- Center Points on its own full-width row beneath the other profile statistics.
- Profile statistics put the value above a quieter label, with consistent row spacing. Last check uses a smaller date treatment than numeric totals; keep all statistic areas tappable and adapt to Dynamic Type.
- Reading history uses open rows with subtle separators, showing only readings with a valid BAC value and their date/time. Omit the entire entry when BAC is unavailable. Saved readings and Last check use the same BAC-qualified entries. Preserve Load more when a filtered page has no visible entries. Do not show sensor source badges, raw counts, durations, acquisition details, a saved-check-ins introduction, or a no-estimate placeholder in this list. Keep the existing validated device BAC gate; backend simulator/manual samples never acquire a numeric BAC through presentation. Explicit finger-generated local practice readings may appear with a visible Simulated % BAC label, and the profile count explains that practice entries are included. Detailed acquisition notices remain in the live test flow.
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
- Show real account data. Explicit practice readings may be saved locally with simulated provenance; never turn them into device measurements, server check-ins or game awards.

## Copy and motion

- Preserve wording the user already likes. Keep new copy short and natural, using Better Writing and Humanizer.
- Use Apple Design and Emil Design Engineering for interface decisions. Use native SwiftUI before adding custom machinery.
- Give immediate press feedback. Keep occasional state transitions around 150 to 250 ms, without decorative looping motion.
- Retain existing auth, camera, history, and account behavior while polishing the interface.
- Home has no Cancel test button. Keep cancellation controls in the separate device and game flows.
- After a completed Home reading, show Test again beside the duration. It clears the displayed result and returns the center circle to Tap the breathalyzer to start. Wait for a fresh NFC tap before arming another test; retain saved history. Stack the controls at accessibility text sizes, and keep the button separately accessible from the duration. Game check-ins keep their existing session flow.

## Home app readings

Liam's latest demo request supersedes live NFC arming: the hardware does not work.
The configured NFC app link starts a six-second local reading flow and saves
exactly 0.00. Holding the center circle keeps the random-value demo. Both are App
readings with local simulated provenance; neither sends an arm, check-in or device
measurement request. Keep actual device BAC validation unchanged.

The idle circle shows Tap your phone to the breathalyzer beneath its center star.
Connect a breathalyzer belongs only in the bottom capsule, without a clock icon or duration. Show the
clock and remaining seconds while the touch-flow countdown is active. When it
finishes, retain the measured elapsed time through processing and completion,
with Test again beside it once ready. Omit Reading saved and Finishing reading
from the bottom capsule. Device results use their reported duration; unavailable
duration stays unavailable. Retain saved data on reset.

Omit the repeated simulation/phone-storage banners and profile footnote. Generated
touch values use the concise App reading label in Home results/accessibility.
Reading history labels all numeric values % BAC, per Liam's latest copy request;
retain the underlying source metadata. Device diagnostic
source copy says Test reading; its source metadata and numeric BAC gate remain
unchanged. The current app-generated records save locally. Cloud persistence
requires the authenticated backend contract in the Nicholas reading-sync handoff;
never infer cloud sync from a local save or fabricate a device measurement.

## Live Party and local-game boundaries

Fresh live Create must use the deployed atomic device-party resolve request, with
durable UUID/body and no fallback to separate create/bind. Open a new room only
after its server response confirms the scanned device binding. Setup failures
keep exact retry available while the sheet is open; never report a new unlinked
party as saved. Existing legacy parties may use explicit binding repair
without creating another party. This supersedes older two-step creation guidance.

Setup errors say only Couldn't set up a linked party, without teammate names or
deployment instructions. Omit Change request throughout Party and setup retry
controls above the Party entry card. Setup errors appear only inside the setup
sheet, never on the Party entry page after closing it or returning to the tab.
Ignore NFC links received during unrelated party/game actions without a navigation
warning. Clear game-screen errors when Trivia closes so they cannot appear above
the party room.
Create a party can recover a pending setup with its saved name and exact Try again
action. Explicit Close or swipe dismissal cancels the unfinished local setup,
clears its saved request, name, scanned device and errors, and restores both join
options. Cancel the client task and ignore late scan/setup callbacks. Confirmed
server parties remain saved; cancelling a draft never silently closes or leaves one.

The latest Party header places the approved Settings icon to the right of the
party name. Hosts get Delete party in that menu. Confirm that this ends the party
for everyone and retains saved readings/game history; the current backend supports
closing, not erasing, party records. Remove the current party only after the server
returns CLOSED with the device released. Hide closed parties from the active list,
retain the room on failure, and preserve Load more when an older page has only
closed rows. Do not offer Use party code instead after linking fails or expose
an invitation code before the device is linked. The deployed atomic resolve and
create/join routes enforce one active OPEN membership per user.


Keep the selected party when switching tabs and restore it for the signed-in
owner on launch. Remove the entire Your parties list, including pagination, list
retry messages and its unused network fetches. Refresh the current party and games
quietly. Neither the Party entry page nor the room has a shared error/request
banner above its content; refresh must not display Couldn't reach KickBAC, save
failures or retained-request/exact-retry explanations. Form failures stay inside
their forms. A pending game write keeps its retry beside the game controls.
Creating a party and scanning a device do not prove a successful server binding.
An unlinked host party offers Link breathalyzer and shows Start a game disabled
until its device_id is confirmed. Existing saved party data is retained.


Party uses authenticated server create/join/read, host binding, game-instance context and private check-ins. Restore the original NFC tap animation in create, join, link and invite flows, with server-issued codes as fallback. Omit QR scanning, raw device-entry fields and My check-ins from Party. The existing Shortcuts NFC automation supplies an app device link; native NFC reading and Universal Links remain unconfigured. Links received on the Party tab stay in Party. An NFC scan immediately sends the authenticated party join and opens the party after server success; omit the found-device status and Join party confirmation button. Keep Join with code as fallback. Joining never arms a test. Linking requires operator authorization. Explicit Start my test creates a check-in and adopts the returned session into the same DeviceSessionStore as Home. Keep source/acquisition notices visible and accessible; manual acquisition is not validated breath and null BAC stays unavailable.

Game sessions provide saved context, not synchronized gameplay. Never submit local Trivia points or infer a public roster from private history. Liam's latest UI request supersedes the earlier disclosure-copy requirement: omit sample, preview, local and unsaved captions from Party/Trivia, including accessibility copy. The old party fixture stays behind the Debug-only Party layout option; KICK26 never enters the live API flow. These copy changes do not connect multiplayer or fabricate a physical reading.

The live entry restores the mint Join a party card, with full-width Join with code and Create a party actions below it. Use an explicit black-on-white primary capsule with a minimum 54-point height; do not rely on inherited glass tint for its label. Keep the header and Settings-style options on one row. Put device management, end/leave and the all-parties action in options. Forms use padded fields on the dark canvas, concise labels, visible errors and full-width actions. Live game selection reuses the approved overlapping cards; unsupported game actions say Coming soon.

## Debug party preview

- Live Party offers authenticated creation, NFC app-link joining and server-code joining. Keep membership separate from explicit check-in and device binding. The Debug fixture retains its instructional artwork and approved layouts, without development banners.
- The host chooses games. Use matching compact colored cards inspired by the supplied Games reference, with KickBAC's rounded system type. Trivia is warm yellow; Pictionary is lavender. Cards use a 164-point minimum height that grows with text, 24-point padding, 28-point corners, and matching 64-point approved game illustrations. Use the final full-color Hi-fi SVG artwork from Trivia `191:235` and Pictionary `191:245`, omitting only the colored rounded-square backing in the app assets. Preserve the paper outlines, pencil, question mark, accent positions, and original rendering without tint or extra icon padding. Use transparent illustrations on the colored cards and game details. Ongoing-game and profile Recent games rows use the same approved artwork on a rounded-square fill drawn from the exact shared card color; never substitute a gradient or a different tint. On game cards, offset the artwork 8 points right and 8 points up to align the foreground with the title. Give card backgrounds an upward black shadow (26% opacity, 4-point radius, y −4) so the front Pictionary card casts a visible seam onto Trivia. Keep Pictionary above Trivia in drawing order. Group title and description with 8-point spacing; omit category labels and their footer chevron. Overlap cards by 56 points so the next card covers the preceding card’s lower curves. A card with another overlapping it reserves a 68-point bottom inset, keeping 12 points clear below growing content. Separate cards by 16 points at accessibility sizes. Never obscure text or artwork to create the stack.
- The game picker uses 24-point horizontal margins, a 12-point top inset, and 20 points between Choose a game and the cards. Keep the flat SplashBackground, native navigation, and a Close action for the sheet; pushed game details use native Back navigation. Preserve useful whitespace instead of adding filler, statistics, or extra explanatory copy.
- Guests see ongoing games, the leaderboard, and people. Omit the ongoing-games section when there are none. Keep leaderboard and people open on the dark canvas.
- Native glass belongs on controls; game cards are colored content surfaces. Profile photos remain softly rounded squares.
- The Debug party preview is ephemeral. Preserve the Settings-style options icon and concise names/copy. No simulated physical result may advance a real check-in.
- Align the party name and Settings-style options button in the same header row, without a star beside the name. Keep device IDs hidden. The code-joined sample is named Party, without a preview suffix.
- Join sheets keep the code field and Join with code action, without You're invited, a standalone NFC icon, tap instructions, or the Join party action. Tap entry shows the shared phone-to-breathalyzer illustration above the code form.
- Use exactly Tap your phone to the breathalyzer as a plain caption beside every tap animation, including Create. Create uses the exact shared illustration/caption as Join; the instruction is not a button and never changes to an NFC icon. No simulated tap selection is required before local creation; require only a valid party name. Do not claim a live NFC connection. Create starts at Party name, without Make it your party.
- Invite people shows the animation and Tap your phone to the breathalyzer, then Or enter code to join above the horizontally centered party code. Omit invitation headings and preview disclaimers.
- The tap illustration uses monochrome filled silhouettes. Stylize the breathalyzer with a smooth rounded body, a rounded left mouthpiece, and no mounting nubs or invented controls. The NFC mark should be large and readable. Loop the approach/hold/withdraw sequence while the scene is active; Reduce Motion shows a static contact pose. The artwork is clipped to its area and ignores touches so inputs remain available.
- Live party creation, code/device joining, host binding and private check-in now use deployed endpoints. The server owns permissions, session identity, expiry and history. Public member names, shared scores and synchronized gameplay are still unavailable. Party joining never arms a test or exposes another person's reading.

## Trivia

The current two-phone flow uses encrypted nearby iPhone connections scoped to the
server-confirmed party/game. The host owns round/category/question/deadline,
answer acceptance, scores and next-round progression; both actual ready peers
must connect before Start trivia enables. Show real connected names and a concise
connection status. Background party polling must be silent and preserve layout.
Share the host's invitation code with nearby party members and show it at the top
on both phones. Local Network permission, Wi-Fi/Bluetooth and proximity are part
of this connection; server membership/game metadata alone is not round transport.
Do not add demo/showcase banners. This supersedes earlier local-round-only notes.


- Automatically offer the compact Trivia invitation after a server-confirmed game starts. Each foreground party member polls the shared game list every two seconds and receives the invitation once per game. Defer it until other sheets close. Background push notifications are not implemented. The entire Join game capsule is tappable.
- Join game opens HomeView directly, without Your check-in, Use an app reading or Start my test pages. Omit the party-room Breathalyzer/Online/Start my test controls. NFC starts the explicitly requested six-second local 0.00 demo; holding the circle produces the random demo. Do not arm or upload a device result. Completion marks only the current phone's local player Ready and retains the simulated BAC flag. Continue without a test retains null BAC. Keep Cancel test while the local flow runs, with Test cancelled only in the center after cancellation. Omit the duplicate bottom cancellation text and BAC will stay unavailable.
- The ready roster shows square avatar, name and one status: Ready with a check, Checking in, Sitting out, or Not ready. Omit BAC and explanatory preview copy here.
- Put Leave game above Start trivia on the ready page. It clears the current player's readiness/check-in and returns to the party without ending anyone else's game.
- The host starts the game; ready players then take turns spinning one shared category/question per round. This supersedes the earlier host-only spinner decision. Tap or drag the wheel itself, tracking the finger before momentum settles it. Rotate the center star with the slices; keep only the pointer fixed. No separate spin button or shared-question explanation.
- Wheel and question/waiting pages never scroll. Adapt to available height and use side-by-side content in landscape. Answer buttons use two columns normally, one at accessibility sizes when height permits. Keep full accessible labels and at least 44-point targets. Reduce Motion skips spinning.
- Use six soft category colors, a continuous horizontal countdown, rounded system type, and 24-point margins. Answer submission locks and acknowledges the choice without revealing correctness, scoring or an outcome haptic. Reveal after everyone answers or the absolute deadline passes.
- Answer choices use solid coral, blue, yellow and green fills with black text. Only the selected choice gains a black outline. Omit Choose your answer and the answered count; keep Answer locked after selection and Sitting out for spectators, with stable status-line space so the layout does not jump.
- Round results are a separate page containing the correct answer, every player's earned points and totals, without an answer explanation. Advance to the next spinner after five seconds, with an explicit Next round action. VoiceOver retains the page until that action. Haptics mark selection separately from the later outcome.
- Final results use a 2–1–3 podium and readable standings list. Omit the Good game introduction and provenance captions. Show only the current player's permitted check-in BAC when available; missing/manual/backend-simulator estimates stay unavailable. Explicit local practice values use the Practice BAC label. BAC never affects rank/reward or enters private history from the game. Accessibility sizes omit decorative podium columns.
- The rounds remain local. Example-roster controls live only in the Debug options menu; roster names use Alex, Sam and Jordan. Practice never arms a session or saves a score; its explicitly simulated readings are local to the phone. Live private check-in is connected; synchronized rounds still require a separate contract.

## Verification

Build with Xcode-beta and use code checks appropriate to the change. Do not use vision or Device Hub unless the user explicitly asks to use them again. A successful build alone does not verify rendering; report that limit accurately.

Debug builds accept `--show-profile` to open Me directly. This changes only the initial selected tab and does not bypass sign-in or supply account data.

Report installation accurately when installing on the connected iPhone. Commit, push, or merge only with explicit permission.
