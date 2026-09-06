"""
Retro Pi 2.0 -- update from inside Kodi.

Runs /usr/local/bin/retropi2-update and turns its STEP:/DONE: output
into a Kodi progress dialog, so updating never needs SSH or a keyboard.
"""

import subprocess
import xbmc
import xbmcgui

ADDON_NAME = "Retro Pi 2.0"
UPDATER = "/usr/local/bin/retropi2-update"

# Weights are rough share-of-time, so the bar moves at a believable rate:
# apt dominates, the rest are quick.
STEPS = [
    ("system", "System packages", 45),
    ("scripts", "Retro Pi 2.0 scripts", 5),
    ("cores", "Emulator cores", 30),
    ("addons", "Kodi add-ons", 20),
]


def run_update(full_upgrade):
    dlg = xbmcgui.DialogProgress()
    dlg.create(ADDON_NAME, "Starting update...")

    cmd = ["sudo", "-n", UPDATER]
    if full_upgrade:
        cmd.append("--full-upgrade")

    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,
        )
    except OSError as exc:
        dlg.close()
        xbmcgui.Dialog().ok(ADDON_NAME, "Could not start the updater:\n%s" % exc)
        return

    done = 0
    results = {}
    restart_needed = False
    current_label = ""

    for raw in proc.stdout:
        line = raw.rstrip("\n")
        xbmc.log("[retropi2-update] " + line, xbmc.LOGINFO)

        if line.startswith("STEP:"):
            parts = line.split(":", 2)
            if len(parts) == 3:
                current_label = parts[2]
                pct = int(done)
                dlg.update(min(pct, 99), current_label)

        elif line.startswith("DONE:"):
            parts = line.split(":", 2)
            if len(parts) == 3:
                key, status = parts[1], parts[2]
                results[key] = status
                weight = next((w for k, _, w in STEPS if k == key), 10)
                done += weight
                dlg.update(min(int(done), 99), current_label)

        elif line.startswith("RESTART:"):
            restart_needed = True

        if dlg.iscanceled():
            # Don't kill apt mid-transaction -- that leaves dpkg broken.
            dlg.update(int(done), "Finishing the current step...")

    proc.wait()
    dlg.update(100, "Done")
    dlg.close()

    if not results:
        xbmcgui.Dialog().ok(
            ADDON_NAME,
            "The updater produced no output.\n\n"
            "Check the log:\n/var/log/retropi2-update.log")
        return

    pretty = {k: lbl for k, lbl, _ in STEPS}
    lines = []
    for key, label, _ in STEPS:
        if key in results:
            mark = "OK" if results[key] == "ok" else "FAILED"
            lines.append("%-22s %s" % (pretty.get(key, key), mark))

    failed = [k for k, v in results.items() if v != "ok"]
    header = "Update finished." if not failed else "Update finished with problems."
    body = header + "\n\n" + "\n".join(lines)
    if failed:
        body += "\n\nDetails: /var/log/retropi2-update.log"

    if restart_needed:
        if xbmcgui.Dialog().yesno(
                ADDON_NAME,
                body + "\n\nKodi was updated and needs to restart.\nRestart now?",
                nolabel="Later", yeslabel="Restart"):
            subprocess.Popen(
                ["sudo", "-n", "systemctl", "restart", "retropi2-kodi.service"])
            return
    else:
        xbmcgui.Dialog().ok(ADDON_NAME, body)


def main():
    choice = xbmcgui.Dialog().select(
        "%s -- Update" % ADDON_NAME,
        [
            "Update everything (recommended)",
            "Full upgrade (may change Kodi version)",
            "Cancel",
        ])

    if choice == 0:
        run_update(full_upgrade=False)
    elif choice == 1:
        if xbmcgui.Dialog().yesno(
                ADDON_NAME,
                "A full upgrade can install a new major version of Kodi.\n\n"
                "That occasionally breaks the skin, and there is no snapshot "
                "to roll back to.\n\nContinue?",
                nolabel="Cancel", yeslabel="Continue"):
            run_update(full_upgrade=True)


if __name__ == "__main__":
    main()
