# Avancement CabinetPro

## Phase 0 — préparation

- [x] Archiver les fichiers de l’ancienne version dans `_old_web_version` sans toucher à `.git`.
- [x] Initialiser le projet Wails v2 React + TypeScript + Vite directement à la racine.
- [x] Vérifier Go, Node.js, npm et Wails avec `wails doctor`.
- [x] Créer le README de l’application de bureau et ce suivi.
- [ ] Faire relire le plan avant de commencer la Phase 1.

### Environnement vérifié

- Go `go1.27.1` — installé
- Node.js `v22.20.0` — installé
- npm `11.10.0` — installé
- Wails CLI `v2.17.0` — installé dans le GOPATH utilisateur
- WebView2 Runtime `155.0.4283.62` — installé
- NSIS — absent, optionnel pour l’installateur

## Phases restantes

1. **Phase 1** — thème Tailwind, police Inter locale, composants réutilisables, shell/navigation, SQLite pur Go, migrations et paramètres du cabinet.
2. **Phase 2** — patients et informations du cabinet.
3. **Phase 3** — agenda et salle d’attente.
4. **Phase 4** — odontogramme.
5. **Phase 5** — actes, plans de traitement, devis, paiements, reçus et impression.
6. **Phase 6** — rappels WhatsApp, ordonnances, certificats et tableau de bord.
7. **Phase 7** — sauvegardes, verrouillage, données de démonstration, finition et installateur.

Chaque phase s’arrête pour revue avant de commencer la suivante.
