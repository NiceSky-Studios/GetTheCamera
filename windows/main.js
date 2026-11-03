const { app, BrowserWindow, ipcMain, dialog, desktopCapturer } = require("electron");
const { execFile } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const ffmpeg = require("ffmpeg-static");

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    backgroundColor: "#111827",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true
    }
  });
  mainWindow.loadFile(path.join(__dirname, "index.html"));
}

app.whenReady().then(createWindow);
app.on("window-all-closed", () => app.quit());

ipcMain.handle("sources:list", async () => desktopCapturer.getSources({
  types: ["screen", "window"],
  thumbnailSize: { width: 320, height: 180 }
}));

ipcMain.handle("clips:list", async () => {
  const directory = path.join(app.getPath("videos"), "GetTheCamera");
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory)
    .filter(name => /\.(mp4|webm|mov|mkv)$/i.test(name))
    .map(name => {
      const filePath = path.join(directory, name);
      return { name, path: filePath, modifiedAt: fs.statSync(filePath).mtimeMs };
    })
    .sort((a, b) => b.modifiedAt - a.modifiedAt);
});

ipcMain.handle("recording:save", async (_event, base64, extension = "webm") => {
  const directory = path.join(app.getPath("videos"), "GetTheCamera");
  fs.mkdirSync(directory, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const output = path.join(directory, `Clip ${timestamp}.${extension}`);
  fs.writeFileSync(output, Buffer.from(base64, "base64"));
  return output;
});

ipcMain.handle("export:clip", async (_event, input, options) => {
  const directory = path.join(app.getPath("videos"), "GetTheCamera", "Exports");
  fs.mkdirSync(directory, { recursive: true });
  const output = path.join(directory, `GetTheCamera ${Date.now()}.${options.format || "mp4"}`);
  const args = ["-y", "-i", input, "-ss", String(options.start || 0), "-to", String(options.end || 999999)];
  if (options.speed && options.speed !== 1) args.push("-filter:v", `setpts=${1 / options.speed}*PTS`, "-filter:a", `atempo=${options.speed}`);
  args.push("-c:v", "libx264", "-c:a", "aac", output);
  return new Promise((resolve, reject) => {
    execFile(ffmpeg, args, error => error ? reject(error.message) : resolve(output));
  });
});

ipcMain.handle("dialog:open", async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    properties: ["openFile"],
    filters: [{ name: "Video", extensions: ["mp4", "mov", "webm", "mkv"] }]
  });
  return result.canceled ? null : result.filePaths[0];
});
