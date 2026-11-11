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
  startNewBinder: () => ipcRenderer.invoke("startNewBinder"),
  deleteMyData: () => ipcRenderer.invoke("deleteMyData"),
  setStartAtLogin: (on) => ipcRenderer.invoke("setStartAtLogin", on === true),
  onStatus: (listener) => {
    const handler = (_event, status) => listener(status);
    ipcRenderer.on("status", handler);
    return () => ipcRenderer.removeListener("status", handler);
  },
});
