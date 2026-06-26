set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

container_compose := env_var_or_default("CONTAINER_COMPOSE", "docker compose")
compose_file := env_var_or_default("COMPOSE_FILE", "compose.yml")

default:
    @just --list

check-container-runtime:
    @compose="{{container_compose}}"; \
      compose_bin="${compose%% *}"; \
      if ! command -v "${compose_bin}" >/dev/null 2>&1; then \
        echo "Erreur: runtime compose introuvable: ${compose_bin}"; \
        echo "Configure CONTAINER_COMPOSE='docker compose', 'podman compose' ou 'podman-compose'."; \
        exit 1; \
      fi

start: check-container-runtime
    @if ! command -v process-compose >/dev/null 2>&1; then echo "Erreur: process-compose n'est pas installe."; exit 1; fi
    @if [ ! -f .env ]; then cp .env.example .env; echo ".env cree depuis .env.example"; fi
    @port=7575; \
      while lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; do port=$((port + 1)); done; \
      if [ "$port" -ne 7575 ]; then echo "Port 7575 occupe, utilisation du port $port"; fi; \
      echo "Homarr: http://localhost:$port"; \
      (sleep 4; open "http://localhost:$port" >/dev/null 2>&1 || true) & \
      HOMARR_PORT="$port" CONTAINER_COMPOSE="{{container_compose}}" COMPOSE_FILE="{{compose_file}}" process-compose -f process-compose.yaml up

stop: check-container-runtime
    @process-compose down || true
    @{{container_compose}} -f {{compose_file}} down

logs: check-container-runtime
    @{{container_compose}} -f {{compose_file}} logs -f homarr

errors: check-container-runtime
    @tmp_file=$(mktemp); \
      {{container_compose}} -f {{compose_file}} logs --no-color --tail=400 homarr > "$tmp_file" 2>&1 || true; \
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

status: check-container-runtime
    @{{container_compose}} -f {{compose_file}} ps

deploy tag="":
    @release_tag="{{tag}}"; \
      if [ -z "$release_tag" ]; then \
        if command -v gum >/dev/null 2>&1; then \
          release_tag="$(gum input --placeholder 'v0.1.0' --prompt 'Release tag: ')"; \
        else \
          read -r -p 'Release tag (vX.Y.Z): ' release_tag; \
        fi; \
      fi; \
      case "$release_tag" in v*) ;; *) echo "Release tag must start with v: $release_tag" >&2; exit 1 ;; esac; \
      test -n "$release_tag"; \
      git diff --quiet; \
      git diff --cached --quiet; \
      if git rev-parse -q --verify "refs/tags/$release_tag" >/dev/null; then \
        echo "Tag already exists: $release_tag" >&2; \
        exit 1; \
      fi; \
      git tag "$release_tag"; \
      git push origin "$release_tag"
