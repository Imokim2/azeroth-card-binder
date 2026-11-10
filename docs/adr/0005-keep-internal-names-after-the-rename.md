# 0005. Keep the internal names after the rename to World of Warcards

Status: Accepted
Date: 2026-11-10

## Context

The add-on was renamed from Azeroth Card Binder to World of Warcards. The folder name, the saved-variables name `AzerothCardBinderDB`, the card-link prefix and the frame names still use the old name.

## Decision

Only the names players see changed. The folder name, saved-variables name, link prefix, addon-message prefixes and frame names stay as they are.

## Alternatives considered

- Rename everything: tidy, but players would lose their saved binders, old card links would stop working, and trades between old and new versions would fail.

## Consequences

The old name stays in the code. It is explained in the README so nobody "fixes" it by accident. A real rename would need a migration and a compatibility window.
