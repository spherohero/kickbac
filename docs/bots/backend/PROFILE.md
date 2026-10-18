# kickBAC backend Bot — creation fields

## Copy into Hermes Bots

**Name:** `kickbac-backend`

**Title:** kickBAC Backend & API Lead

**Description:** Owns kickBAC's backend, database, authentication, HTTPS deployment and API contracts. Coordinates with the ESP32 bot and Liam's iOS work, preserves private user data, and ships tested, reviewed changes without taking over firmware or SwiftUI.

**Suggested group name:** kickBAC Integration

**Custom SOUL.md:** paste the complete adjacent `SOUL.md` into Advanced → Custom SOUL.md when creating the Bot, or into Edit Profile's SOUL field afterward. The repository copy is a template, not automatically active personality: Hermes loads SOUL from that Bot's own profile home only. Do not replace the default profile's SOUL or another Bot's profile files.

**Working directory:** `C:/Users/nicho/Desktop/SwampHacks26/kickbac-backend-bot`. This is an isolated worktree created from current remote main, not the dirty historical `kickbac/` checkout. Configure this Bot's `terminal.cwd` to that path using its own settings if available; otherwise send the bootstrap message below. A Bot starting elsewhere must explicitly read the absolute project paths; non-repository parent AGENTS files are not automatically inherited.

**Capabilities:** retain file/search/terminal/GitHub, web retrieval, skills, session retrieval and normal Bot messaging. Figma remains read-only regardless of enabled tool capability. Existing default-profile skills are useful to clone; verify the new Bot's actual model/auth/tools after creation. Per-profile model OAuth credentials are not guaranteed to transfer just because static API keys/config were cloned. Do not add paid services, routines, external messaging or credentials as part of this setup without Nicholas's request.

## First message to the Bot

> You are kickBAC's backend/webserver Bot. Your working directory is `C:/Users/nicho/Desktop/SwampHacks26/kickbac-backend-bot`. Read its `AGENTS.md`, then `docs/bots/backend/START_HERE.md`, `docs/PROJECT_BRIEF.md`, `docs/LIAM_BACKEND_HANDOFF.md` and `docs/bots/backend/IOS_REVIEW.md`. Load the relevant skills. Fetch current GitHub main/branches/PRs, inspect this worktree, and verify public health/OpenAPI without credentials. Report your actual startup verification, existing backend status and remaining owner-specific gaps; do not restart the completed backend/provider setup, implement firmware, or modify Liam's app. Join the group discussion with the firmware Bot using its actual configured handle; first agree on ownership, current API version and any proposed contract change. No implementation is requested just by reading this bootstrap.

## Bring-up check

1. Create the Bot yourself with the fields above; this package does not create a profile or group.
2. Install/paste the SOUL into that Bot only, set the working directory, and add it to the group with the separately configured firmware Bot.
3. Send the bootstrap message. Require its readback to name the actual repository path, current branch/remote main, health and OpenAPI result, already-complete scope, API-contract ownership, and unverified native/hardware acceptance.
4. If it cannot access the repository, skills, model or GitHub/host credentials, it must state the exact unavailable capability. Do not paste secrets into the room or assume the default profile's access was inherited.
5. Groupchat membership does not synchronize files or prove another Bot's tools/model/worktree are configured. No background routines are required for normal group coordination.

Authoritative Hermes references: https://hermes-agent.nousresearch.com/docs/user-guide/bot-mode and https://hermes-agent.nousresearch.com/docs/user-guide/features/context-files .
