# Application OmniCore pour iPhone (sans compte développeur payant)

Une coquille légère, comme l'app Android : OmniCore en plein écran sans Safari, connexion par le même QR code
(`omnicore://pair`), lecture qui continue écran verrouillé, AirPlay et image dans l'image.

Coût : 0 €. L'app est compilée gratuitement par GitHub, puis installée et signée sur l'iPhone par **SideStore**
avec ton identifiant Apple gratuit.

## Ce qui est automatique

1. Tu envoies ce dossier sur GitHub (branche `main`).
2. GitHub compile l'app sur un Mac (`.github/workflows/build.yml`), publie `OmniCore.ipa` et met à jour `source.json`.
3. SideStore lit `source.json` et propose la nouvelle version.
4. Une automatisation Raccourcis renouvelle l'app chaque nuit : la limite des 7 jours ne se voit plus.

## Mise en place (une seule fois)

### 1. Le dépôt GitHub
- Crée un compte GitHub gratuit, puis un dépôt **public** nommé `omnicore-ios`.
  Public, car un dépôt public a des Mac de compilation gratuits sans limite, et SideStore doit pouvoir télécharger l'IPA.
  Le dépôt ne contient que cette coquille : aucune adresse, aucun mot de passe, aucune clé.
- Copie le contenu de `apps/omnicore-ios/` à la racine de ce dépôt (y compris `.github/`) et envoie-le sur `main`.
- Onglet « Actions » : la compilation prend environ 5 minutes. La version apparaît dans « Releases ».

### 2. SideStore sur l'iPhone
- Installe SideStore en suivant le guide officiel : https://docs.sidestore.io (un ordinateur est nécessaire une seule fois).
- Dans SideStore : « Sources », « + », puis colle
  `https://raw.githubusercontent.com/<ton-compte>/omnicore-ios/main/source.json`
- Installe OmniCore depuis cette source.

### 3. Renouvellement automatique
- App Raccourcis, « Automatisation », « + », « Heure de la journée » : 3 h, tous les jours.
- Action : SideStore, « Refresh All Apps ». Choisis « Exécuter immédiatement ».

### 4. Connexion à OmniCore
- Dans l'admin d'OmniCore : « Connecter un appareil par QR code », onglet « Application OmniCore ».
- Scanne le QR code avec l'appareil photo : l'app s'ouvre et se connecte.
- Hors de la maison : installe l'app gratuite Tailscale. Une app avec un identifiant Apple gratuit ne peut pas embarquer Tailscale comme le fait l'app Android.

## Limites de l'identifiant Apple gratuit
- 3 apps installées par SideStore au maximum (SideStore compte pour une).
- Signature valable 7 jours : l'automatisation la renouvelle. Si l'iPhone reste éteint plus de 7 jours, ouvre SideStore et touche « Refresh ».
- Le bouton « Télécharger le fichier » d'OmniCore ne fonctionne pas dans cette app.

## Construire à la main sur un Mac
```
brew install xcodegen
xcodegen generate
open OmniCore.xcodeproj
```
