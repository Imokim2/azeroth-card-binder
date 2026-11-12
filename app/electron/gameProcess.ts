import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { resolve } from "node:path";
const execute = promisify(execFile);

// Any WoW client prevents restoration, including elevated clients whose path cannot be read.
// No process is closed or killed. Failure to inspect processes never counts as a closed game.
export async function gameClosed(folder: string): Promise<boolean> {
  if (process.platform !== "win32") return false;
  const encoded = Buffer.from(resolve(folder), "utf8").toString("base64");
  const script = "$ErrorActionPreference='Stop'; $folder=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded
    + "')); $names=@('Wow.exe','WowClassic.exe','WowB.exe','WowT.exe','WowForever.exe'); Get-ChildItem -LiteralPath $folder -Filter '*.exe' -File | ForEach-Object { if($_.VersionInfo.ProductName -like 'World of Warcraft*') { $names += $_.Name } }; $found=@(Get-CimInstance Win32_Process | Where-Object { $_.Name -in $names }); if($found.Count -eq 0){exit 0}else{exit 1}";
  try {
    await execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], { timeout: 8_000, windowsHide: true });
    return true;
  } catch { return false; }
}
