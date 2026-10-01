# Automatic Deploy

Bezpieczny, powtarzalny pipeline wdrożeniowy w Bash dla środowisk development, staging i production.

- [Dokumentacja polska](docs/README.pl.md)
- [English documentation](docs/README.en.md)

## Szybki start

```bash
git clone https://github.com/Xmausix/Automatic-Deploy.git
cd Automatic-Deploy
chmod +x deploy.sh rollback.sh chatops.sh menu.sh
./deploy.sh development --dry-run
```

Projekt wymaga Bash 4.2+ oraz Git. Integracje z Dockerem, Vault, Trivy/Grype, GPG, systemd i webhookami są opcjonalne. Przed produkcyjnym użyciem uzupełnij `config/*.conf`, nie zapisuj sekretów w repozytorium i uruchom `--dry-run`.

## Zasady bezpieczeństwa

Konfiguracja jest walidowana, wartości są przekazywane bez `eval`, webhooki mają timeout, kopia zapasowa powstaje przed zmianą, a wdrożenie można wycofać przez `rollback.sh`. Pliki `logs/`, `backups/`, `releases/` i `reports/` są danymi wykonawczymi i nie powinny zawierać się w commitach.
