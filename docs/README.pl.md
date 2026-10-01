# Automatic Deploy — dokumentacja

## Cel

Narzędzie uruchamia kontrolowane wdrożenie aplikacji: waliduje konfigurację, pobiera wskazany branch, wykonuje backup, buduje i testuje aplikację, opcjonalnie skanuje obraz, wdraża, restartuje usługę i wykonuje health check. Nieudany health check uruchamia rollback.

## Wymagania

Bash 4.2+, Git i narzędzia używane przez projekt. `curl`, `rsync`, Docker, systemd, `jq`, Vault, Trivy/Grype, GPG oraz `dialog` są opcjonalne zależnie od konfiguracji.

## Konfiguracja

Edytuj odpowiedni plik w `config/`. Najważniejsze zmienne:

| Zmienna | Znaczenie |
|---|---|
| `APP_DIR` | katalog aplikacji |
| `BRANCH` | branch wdrażany |
| `SERVICE_NAME` | usługa systemd lub kontener |
| `DEPLOY_STRATEGY` | `local`, `rolling`, `blue-green`, `canary` |
| `HOSTS` | hosty rozdzielone spacją; `localhost` dla wdrożenia lokalnego |
| `HEALTH_URL` | endpoint gotowości |
| `HEALTH_TIMEOUT` | maksymalny czas health checku w sekundach |
| `VAULT_PATH` | opcjonalna ścieżka Vault KV |

Webhooki i tokeny przechowuj poza repozytorium, np. w menedżerze sekretów lub środowisku procesu.

## Użycie

```bash
./deploy.sh development --dry-run
./deploy.sh staging --strategy rolling
./deploy.sh production --strategy blue-green
./deploy.sh production --skip-tests
./rollback.sh production backup_YYYYMMDD_HHMMSS_production --dry-run
./menu.sh
```

`--skip-tests` i `--skip-security` wymagają świadomej decyzji i powinny być ograniczone do wyjątkowych sytuacji. `--parallel` uruchamia wdrożenia na wielu hostach równolegle; używaj go tylko wtedy, gdy aplikacja i infrastruktura są na to gotowe.

## Przebieg i artefakty

Wyniki trafiają do `logs/`, kopie do `backups/`, artefakty do `releases/`, a raporty do `reports/`. Metryki Prometheus są zapisywane jako pliki `.prom`. Nie commituj tych katalogów ani plików z sekretami.

## Operacje produkcyjne

1. Zweryfikuj konfigurację i uprawnienia katalogów.
2. Wykonaj dry-run.
3. Uruchom testy i skan bezpieczeństwa.
4. Monitoruj health check, logi i raport.
5. W razie niepowodzenia użyj rollbacku i sprawdź stan usługi.

Prosty listener ChatOps jest demonstracyjny. Do produkcji użyj uwierzytelnionego endpointu za reverse proxy, z walidacją podpisu, ograniczeniem dostępu, rate limitingiem i kolejką zadań.
