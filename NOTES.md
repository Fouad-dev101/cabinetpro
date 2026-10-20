# Notes de conception

- Application Windows mono-utilisateur, mono-ordinateur, fonctionnant hors ligne.
- Le fichier SQLite local est la source de données; aucune synchronisation ou base hébergée n’est prévue.
- L’interface et tous les messages visibles seront en français, centralisés dans `frontend/src/lib/fr.ts`.
- Les sommes seront stockées en centimes entiers; les dates seront stockées au format ISO.
- Les patients seront archivés avec `archived_at`; les suppressions de données demanderont confirmation.
- Le template Wails choisi est React + Vite + TypeScript (`react-ts`).
- L’ancienne application web est conservée à la racine dans `_old_web_version`; elle ne sera pas utilisée par l’application bureau.
- La police Inter doit être distribuée localement dans l’application, sans CDN. Sa source et sa licence devront être documentées lors de la Phase 1.
- NSIS est absent; la production d’un installateur dépendra de son installation ou d’une autre option gratuite validée.

## Schéma SQLite prévu

Toutes les tables métier auront `id INTEGER PRIMARY KEY AUTOINCREMENT`, `created_at` et `updated_at`. Les montants monétaires sont des entiers en centimes.

- `clinic_settings`: `clinic_name`, `doctor_name`, `specialty`, `address`, `city`, `phone`, `logo_path`, `ice`, `opening_hours`, `slot_minutes`, `whatsapp_template`, `app_lock_hash`.
- `patients`: `last_name`, `first_name`, `phone`, `phone_2`, `cin`, `birth_date`, `gender`, `address`, `city`, `mutuelle_amo`, `allergies`, `medical_history`, `general_notes`, `archived_at`.
- `appointments`: `patient_id`, `starts_at`, `duration_minutes`, `reason`, `notes`, `status`.
- `tooth_records`: `patient_id`, `tooth_number`, `state`, `note`, `recorded_at`.
- `acts`: `name`, `default_price_cents`, `active`.
- `treatment_plans`: `patient_id`, `status`.
- `treatment_lines`: `plan_id`, `act_id`, `tooth_number`, `price_cents`, `discount_cents`, `status`.
- `payments`: `patient_id`, `amount_cents`, `paid_at`, `method`, `note`.
- `reminders`: `appointment_id`, `sent_at`.
- `prescriptions`: `patient_id`, `date`, `content` (JSON).
- `certificates`: `patient_id`, `date`, `content`.
- `schema_migrations`: `version`, `applied_at` (migration bookkeeping).

Les index prévus sont `patients(last_name, first_name, phone)`, `appointments(starts_at)` et `payments(patient_id)`.
