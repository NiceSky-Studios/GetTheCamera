const { app, BrowserWindow, ipcMain, dialog, desktopCapturer, shell } = require("electron");
const { execFile, spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const ffmpeg = require("ffmpeg-static");
const https = require("node:https");

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

app.whenReady().then(() => {
  createWindow();
  setTimeout(() => checkForUpdates(true).catch(error => {
    console.error("Automatic update check failed:", error);
  }), 10_000);
});
app.on("window-all-closed", () => app.quit());

function downloadFile(url, destination, sendProgress) {
  return new Promise((resolve, reject) => {
    const request = (currentUrl, redirects = 0) => {
      https.get(currentUrl, {
        headers: { "User-Agent": `GetTheCamera/${app.getVersion()}`, Accept: "application/octet-stream" }
      }, response => {
        if ([301, 302, 307, 308].includes(response.statusCode) && response.headers.location && redirects < 5) {
          response.resume();
          return request(response.headers.location, redirects + 1);
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          response.resume();
          return reject(new Error(`Download failed (${response.statusCode})`));
        }
        const file = fs.createWriteStream(destination);
        const total = Number(response.headers["content-length"] || 0);
        let downloaded = 0;
        response.on("data", chunk => {
          downloaded += chunk.length;
          if (total && sendProgress) sendProgress(Math.round(downloaded / total * 100));
        });
        response.pipe(file);
        file.on("finish", () => file.close(resolve));
        file.on("error", reject);
      }).on("error", reject);
    };
    request(url);
  });
}

async function checkForUpdates(silent = false) {
  const response = await fetch("https://api.github.com/repos/NiceSky-Studios/GetTheCamera/releases/latest", {
    headers: { Accept: "application/vnd.github+json", "User-Agent": `GetTheCamera/${app.getVersion()}` }
  });
  if (!response.ok) throw new Error(`Update check failed (${response.status})`);
  const release = await response.json();
  const latest = (release.tag_name || "").replace(/^v/i, "");
  const compare = (a, b) => {
    const left = a.split(".").map(Number);
    const right = b.split(".").map(Number);
    for (let index = 0; index < Math.max(left.length, right.length); index++) {
      const difference = (left[index] || 0) - (right[index] || 0);
      if (difference) return difference;
    }
    return 0;
  };
  if (compare(latest, app.getVersion()) <= 0) return { status: "up-to-date", version: app.getVersion() };

  const setup = release.assets?.find(asset => /windows.*setup.*\.exe$/i.test(asset.name))
    || release.assets?.find(asset => /setup.*\.exe$/i.test(asset.name) || /GetTheCamera.*\.exe$/i.test(asset.name));
  if (!setup) return { status: "no-installer", version: latest, url: release.html_url };

  if (!silent) {
    const choice = await dialog.showMessageBox(mainWindow, {
      type: "info",
      title: "Update available",
      message: `GetTheCamera ${latest} is available`,
      detail: `You are running ${app.getVersion()}. Download and install it now?`,
      buttons: ["Update and Relaunch", "Not Now"],
      defaultId: 0,
      cancelId: 1
    });
    if (choice.response !== 0) return { status: "declined", version: latest };
  }

  mainWindow?.webContents.send("updates:progress", { status: "downloading", percent: 0 });
  const destination = path.join(app.getPath("temp"), setup.name);
  await downloadFile(setup.browser_download_url, destination, percent => {
    mainWindow?.webContents.send("updates:progress", { status: "downloading", percent });
  });
  mainWindow?.webContents.send("updates:progress", { status: "installing", percent: 100 });
  spawn(destination, ["/S"], { detached: true, stdio: "ignore" }).unref();
  setTimeout(() => app.quit(), 500);
  return { status: "installing", version: latest };
}

ipcMain.handle("updates:check", async () => {
  try {
    return await checkForUpdates(false);
  } catch (error) {
    return { status: "error", message: error.message };
  }
});

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
