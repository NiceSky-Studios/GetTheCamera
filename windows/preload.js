const { contextBridge, ipcRenderer, webFrame } = require("electron");

contextBridge.exposeInMainWorld("getTheCamera", {
  listSources: () => ipcRenderer.invoke("sources:list"),
  listClips: () => ipcRenderer.invoke("clips:list"),
  saveRecording: (base64, extension) => ipcRenderer.invoke("recording:save", base64, extension),
  exportClip: (input, options) => ipcRenderer.invoke("export:clip", input, options),
  openClip: () => ipcRenderer.invoke("dialog:open"),
  setZoom: zoom => webFrame.setZoomFactor(zoom)
});
