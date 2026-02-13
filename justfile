set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

default:
    @just --list

start:
    @if ! command -v colima >/dev/null 2>&1; then echo "Erreur: colima n'est pas installe."; exit 1; fi
    @if ! command -v docker >/dev/null 2>&1; then echo "Erreur: docker CLI n'est pas installe."; exit 1; fi
    @if ! command -v process-compose >/dev/null 2>&1; then echo "Erreur: process-compose n'est pas installe."; exit 1; fi
    @if ! docker info >/dev/null 2>&1; then \
      echo "Demarrage de Colima..."; \
      if ! colima start; then \
        echo "colima start a echoue, tentative de fallback avec --disk 100..."; \
        colima start --disk 100; \
      fi; \
    fi
    @if [ ! -f .env ]; then cp .env.example .env; echo ".env cree depuis .env.example"; fi
    @port=7575; \
      while lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do port=$((port + 1)); done; \
      if [ "$port" -ne 7575 ]; then echo "Port 7575 occupe, utilisation du port $port"; fi; \
      echo "Homarr: http://localhost:$port"; \
      (sleep 4; open "http://localhost:$port" >/dev/null 2>&1 || true) & \
      HOMARR_PORT="$port" process-compose -f process-compose.yaml up

stop:
    @process-compose -f process-compose.yaml down || true
    @docker compose down

logs:
    @docker compose logs -f homarr

errors:
    @if ! command -v docker >/dev/null 2>&1; then echo "Erreur: docker CLI n'est pas installe."; exit 1; fi
    @tmp_file=$(mktemp); \
      docker compose logs --no-color --tail=400 homarr > "$tmp_file" 2>&1 || true; \
      if command -v rg >/dev/null 2>&1; then \
        rg -i -n "error|fatal|exception|failed|panic|traceback" "$tmp_file" > "$tmp_file.filtered" || true; \
      else \
        grep -Ei -n "error|fatal|exception|failed|panic|traceback" "$tmp_file" > "$tmp_file.filtered" || true; \
      fi; \
      if [ -s "$tmp_file.filtered" ]; then \
        tail -n 120 "$tmp_file.filtered" | tee /dev/stderr | pbcopy; \
        echo ""; \
        echo "Erreurs copiees dans le presse-papiers (120 lignes max)."; \
      else \
        tail -n 120 "$tmp_file" | tee /dev/stderr | pbcopy; \
        echo ""; \
        echo "Aucun pattern d'erreur trouve, dernieres lignes copiees dans le presse-papiers."; \
      fi; \
      rm -f "$tmp_file" "$tmp_file.filtered"

status:
    @docker compose ps
