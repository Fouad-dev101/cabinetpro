# CabinetPro — application de bureau

CabinetPro est une application Windows hors ligne destinée aux cabinets dentaires au Maroc. Les données seront enregistrées localement dans un fichier SQLite. L’interface sera en français, avec les montants en dirhams marocains.

## État du projet

Le projet Wails v2 avec React, TypeScript et Vite est initialisé. Les fonctions métier et l’interface CabinetPro seront ajoutées par phases. Consultez [PROGRESS.md](PROGRESS.md) pour l’avancement et [NOTES.md](NOTES.md) pour les décisions prises.

## Prérequis de développement

- Windows avec WebView2 Runtime
- Go
- Node.js et npm
- Wails v2

Le CLI Wails a été installé pour l’utilisateur avec `go install github.com/wailsapp/wails/v2/cmd/wails@latest`. Si `wails` n’est pas reconnu, ajoutez le dossier retourné par `go env GOPATH` suivi de `\bin` au `PATH`, puis ouvrez un nouveau terminal. Vérifiez l’environnement avec `wails doctor`.

## Démarrer et construire

Depuis le dossier du projet :

```powershell
npm install --prefix frontend
wails dev
```

Pour construire l’application Windows :

```powershell
wails build
```

La création d’un installateur NSIS nécessitera NSIS, qui est facultatif et n’est pas installé dans l’environnement actuel. Aucun service hébergé, compte, clé API, analytique ou police distante ne fait partie de l’application.

## Ancienne version web

Les fichiers de l’ancienne version web sont conservés dans [`_old_web_version`](_old_web_version). Le dépôt Git à la racine est conservé.
