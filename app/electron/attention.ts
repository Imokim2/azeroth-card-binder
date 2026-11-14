// Background sync may change the tray hint, but must never interrupt a game.
// Only an explicit open action may restore, show or focus the companion window.
type CompanionWindow = { isMinimized(): boolean; restore(): void; show(): void; focus(): void };
type CompanionTray = { setToolTip(text: string): void };

export function windowActions(window: () => CompanionWindow | null, tray: () => CompanionTray | null,
  onOpen: () => void) {
  return {
    open(): void {
      const current = window();
      if (!current) return;
      if (current.isMinimized()) current.restore();
      current.show();
      current.focus();
      tray()?.setToolTip("World of Warcards");
      onOpen();
    },
    syncIssue(): void {
      tray()?.setToolTip("World of Warcards — Collection sync needs attention. Open the companion when convenient.");
    },
  };
}
