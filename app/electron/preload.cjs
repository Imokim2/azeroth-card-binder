"use strict";
// The only bridge between the window's page and the app: a fixed list of requests, and a way to hear about changes.
// The page gets no Node, no files and no network from this; it can only ask the controller for these things.
const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("warcards", {
  status: () => ipcRenderer.invoke("status"),
  signIn: (visibility) => ipcRenderer.invoke("signIn", visibility === "private" ? "private" : "public"),
  signOut: () => ipcRenderer.invoke("signOut"),
  chooseGameFolder: () => ipcRenderer.invoke("chooseGameFolder"),
  findGame: () => ipcRenderer.invoke("findGame"),
  syncNow: () => ipcRenderer.invoke("syncNow"),
  repairSync: () => ipcRenderer.invoke("repairSync"),
  startNewBinder: () => ipcRenderer.invoke("startNewBinder"),
  deleteMyData: () => ipcRenderer.invoke("deleteMyData"),
  guildPanel: () => ipcRenderer.invoke("guildPanel"),
  guildRequest: (character, name) => ipcRenderer.invoke("guildRequest", String(character), String(name)),
  guildJoin: (character, name) => ipcRenderer.invoke("guildJoin", String(character), String(name)),
  guildDecide: (member, decision) => ipcRenderer.invoke("guildDecide", String(member), decision === "approve" ? "approve" : "refuse"),
  guildLeave: () => ipcRenderer.invoke("guildLeave"),
  guildRemove: (member) => ipcRenderer.invoke("guildRemove", String(member)),
  exportMyData: () => ipcRenderer.invoke("exportMyData"),
  setStartAtLogin: (on) => ipcRenderer.invoke("setStartAtLogin", on === true),
  updateAddon: () => ipcRenderer.invoke("updateAddon"),
  updateApp: () => ipcRenderer.invoke("updateApp"),
  checkForUpdates: () => ipcRenderer.invoke("checkForUpdates"),
  onStatus: (listener) => {
    const handler = (_event, status) => listener(status);
    ipcRenderer.on("status", handler);
    return () => ipcRenderer.removeListener("status", handler);
  },
});
