"""Ajoute la version compilée en tête de source.json (format des sources SideStore et AltStore) ; garde les 5 dernières."""
import datetime
import json
import os
import sys

version, ipa, repo = sys.argv[1:4]
raw = f"https://raw.githubusercontent.com/{repo}/main"
icon = f"{raw}/OmniCore/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

with open("source.json", encoding="utf-8") as file:
    source = json.load(file)

app = source["apps"][0]
entry = {
    "version": version,
    "date": datetime.date.today().isoformat(),
    "downloadURL": f"https://github.com/{repo}/releases/download/v{version}/OmniCore.ipa",
    "size": os.path.getsize(ipa),
    "minOSVersion": "16.0",
    "localizedDescription": "Mise à jour automatique.",
}
source["iconURL"] = icon
app["iconURL"] = icon
app["versions"] = [entry] + [old for old in app.get("versions", []) if old.get("version") != version][:4]
# Champs de l'ancien format, lus par les versions plus anciennes de SideStore.
app.update({"version": version, "versionDate": entry["date"], "downloadURL": entry["downloadURL"], "size": entry["size"]})

with open("source.json", "w", encoding="utf-8") as file:
    json.dump(source, file, ensure_ascii=False, indent=2)
    file.write("\n")
