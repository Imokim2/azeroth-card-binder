// The Electron shell: a window and a tray icon around the controller. This file only supplies what needs Electron (the
// window, the tray, the folder dialog, opening the browser, the system's key protection); everything the app actually
// does is in src/controller.ts, which is tested without a screen.
//
// The window can only ask the controller for a fixed list of things, through the preload script; it has no access to
// Node, files or the network, and it cannot open other pages.
import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, safeStorage, session, shell, Tray } from "electron";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { SERVERS } from "../src/config.ts";
import { Controller } from "../src/controller.ts";
import type { Status } from "../src/controller.ts";
import { encryptedFileStore } from "../src/secrets.ts";

const here = dirname(fileURLToPath(import.meta.url));
const appRoot = join(here, "..", "..", ".."); // the app/ folder, from app/dist/app/electron
const version = JSON.parse(await readFile(join(appRoot, "package.json"), "utf8")).version as string;

app.setName("World of Warcards");
// A separate data folder for tests and screenshots, so they never touch the real settings or key.
if (process.env["WARCARDS_DATA"]) app.setPath("userData", process.env["WARCARDS_DATA"]);
else app.setPath("userData", join(app.getPath("appData"), "World of Warcards"));

if (!app.requestSingleInstanceLock()) app.quit();

let window: BrowserWindow | null = null;
let tray: Tray | null = null;
let quitting = false;
let controller: Controller;

const DISCORD_PAGE = "https://discord.com/oauth2/authorize?";

function showWindow(): void {
  if (!window) return;
  if (window.isMinimized()) window.restore();
  window.show();
  window.focus();
}

function createWindow(): BrowserWindow {
  const created = new BrowserWindow({
    width: 780, height: 820, minWidth: 640, minHeight: 600, show: false, backgroundColor: "#16110d", title: "World of Warcards",
    icon: join(appRoot, "assets", "icon.png"),
    webPreferences: { preload: join(appRoot, "electron", "preload.cjs"), contextIsolation: true, sandbox: true, nodeIntegration: false, spellcheck: false },
  });
  created.removeMenu();
  // The window shows only our own page: no navigation, no new windows, no permissions.
  created.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  created.webContents.on("will-navigate", (event) => event.preventDefault());
  session.defaultSession.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  // Closing the window sends the app to the tray: syncing carries on, and the heavy part of the window is released.
  created.on("close", (event) => {
    if (quitting) return;
    event.preventDefault();
    created.hide();
  });
  void created.loadFile(join(appRoot, "electron", "renderer", "index.html"), process.env["WARCARDS_DEMO"] ? { hash: "demo-" + process.env["WARCARDS_DEMO"] } : {});
  return created;
}

function send(status: Status): void {
  if (window && !window.isDestroyed()) window.webContents.send("status", status);
}

function buildTray(): void {
  tray = new Tray(nativeImage.createFromPath(join(appRoot, "assets", "tray.png")));
  tray.setToolTip("World of Warcards");
  tray.on("click", showWindow);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: "Open World of Warcards", click: showWindow },
    { label: "Sync now", click: () => void controller.syncNow() },
    { type: "separator" },
    { label: "Quit", click: () => { quitting = true; app.quit(); } },
  ]));
}

app.on("second-instance", showWindow);
app.on("before-quit", () => { quitting = true; });
app.on("window-all-closed", () => { /* the app stays in the tray */ });

// Everything that needs the app to be ready runs inside main(). It is started from `.then`, not awaited at the top of
// the file: a top-level await on whenReady() in a module entry point stops Electron from ever becoming ready.
async function main(): Promise<void> {

  let catalogVersion = "unknown";
  try {
    catalogVersion = JSON.parse(await readFile(join(appRoot, "..", "packages", "shared", "catalog.json"), "utf8")).catalogVersion;
  } catch {
    // Not found next to the app (a packaged build bundles it); the server only needs some text here.
  }

  const userData = app.getPath("userData");
  controller = new Controller({
    dataFolder: userData,
    secrets: encryptedFileStore(join(userData, "key.bin"), {
      available: () => safeStorage.isAsyncEncryptionAvailable(),
      encrypt: (text) => safeStorage.encryptStringAsync(text),
      decrypt: async (bytes) => (await safeStorage.decryptStringAsync(Buffer.from(bytes))).result,
    }),
    server: process.env["WARCARDS_SERVER"] ?? SERVERS.staging,
    version, catalogVersion,
    open: (url) => {
      // Only Discord's own sign-in page is ever opened.
      if (!url.startsWith(DISCORD_PAGE)) throw new Error("refusing to open an address that is not Discord's sign-in");
      return shell.openExternal(url);
    },
    chooseFolder: async () => {
      const result = await dialog.showOpenDialog(window as BrowserWindow, { title: "Choose your World of Warcraft folder", properties: ["openDirectory"] });
      return result.canceled ? null : (result.filePaths[0] ?? null);
    },
    confirm: async (message, button) => {
      const answer = await dialog.showMessageBox(window as BrowserWindow, { type: "warning", buttons: [button, "Cancel"], defaultId: 1, cancelId: 1, title: "World of Warcards", message });
      return answer.response === 0;
    },
    fetch: (url, init) => fetch(url, init as RequestInit),
    now: () => Math.floor(Date.now() / 1000),
    sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    applyStartAtLogin: (on) => app.setLoginItemSettings({ openAtLogin: on }),
    commonFolders: [
      "C:\\Program Files (x86)", "C:\\Program Files", "C:\\Games", "C:\\Blizzard", "D:\\Games", "D:\\Program Files (x86)", "D:\\", "E:\\Games",
    ],
  });
  controller.onStatus(send);

  // What the window may ask for. Each answer is checked; nothing else is reachable.
  ipcMain.handle("status", () => controller.status());
  ipcMain.handle("signIn", (_event, visibility: unknown) => controller.signIn(visibility === "private" ? "private" : "public"));
  ipcMain.handle("signOut", () => controller.signOut());
  ipcMain.handle("chooseGameFolder", () => controller.chooseGameFolder());
  ipcMain.handle("findGame", () => controller.findGame());
  ipcMain.handle("syncNow", () => controller.syncNow());
  ipcMain.handle("startNewBinder", () => controller.startNewBinder());
  ipcMain.handle("deleteMyData", () => controller.deleteMyData());
  ipcMain.handle("setStartAtLogin", (_event, on: unknown) => controller.setStartAtLogin(on === true));

  window = createWindow();
  // Listen for the page loading before anything else is awaited, so the event cannot be missed.
  const loaded = new Promise<void>((resolve) => window?.webContents.once("did-finish-load", () => resolve()));
  buildTray();
  await controller.start();
  await loaded;

  const shot = process.env["WARCARDS_SCREENSHOT"];
  {
    if (shot) {
      // For checking the screen without a person: draw it, save a picture and quit.
      window?.show();
      setTimeout(async () => {
        const image = await window?.webContents.capturePage();
        if (image) await writeFile(shot, image.toPNG());
        quitting = true;
        app.quit();
      }, 900);
    } else {
      // Start hidden in the tray when everything is already set up; otherwise show the window to finish setting up.
      const status = controller.status();
      if (!status.signedIn || !status.gameFolder || status.problem) showWindow();
    }
  }
}

void app.whenReady().then(main);
