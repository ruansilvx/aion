---
ticketId: AIO-6
type: idea
status: done
priority: none
parentId: null
estimate: null
timeSpent: null
createdAt: 2026-07-28T00:00:00.000
updatedAt: 2026-08-24T00:00:00.000
deletedAt: null
estimateRollup: null
timeSpentRollup: null
---
# Aion has no real app icon

Aion has no real app icon yet on any platform — macOS, Windows .ico, and
Android mipmaps all still ship Flutter's default template icon (the blue
Flutter logo). This surfaced while building the
repo-release-setup-and-distribution change's Linux AppImage/Windows
installer packaging, which needed an icon asset and had nothing real to
point at (aion/assets/icons/aion_icon.png currently just stages a copy of
the same placeholder). Needs real Aion branding/icon design at some point
before this ships beyond developer/tester use.