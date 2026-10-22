#!/bin/sh
# VisionAI Edge - remote decommission watchdog (runs in the visionai-watchdog container)
#
# Polls the cloud dashboard with this site's API token. Regenerating or deleting the
# site token in the dashboard makes the cloud answer 401 to this check. When that has
# been the case continuously for DECOMMISSION_AFTER_MINUTES, the watchdog removes the
# whole deployment from this box (containers, models volume, images, local data, .env)
# and finally itself. No access to the box is needed.
#
# Only a 401 from GET <VISIONAI_API_ENDPOINT>/token-details counts. Network errors,
# 5xx, 404 etc. never count and never reset the timer. A 200 resets it.
set -u
API="${VISIONAI_API_ENDPOINT%/}"
TOKEN="${VISIONAI_API_TOKEN:-}"
INTERVAL="${WATCHDOG_INTERVAL_SECONDS:-300}"
AFTER_MIN="${DECOMMISSION_AFTER_MINUTES:-120}"
ENABLED="${DECOMMISSION_ENABLED:-1}"
SELF_IMAGE="${WATCHDOG_IMAGE:-docker:27-cli}"
REPO_HOST_PATH="${REPO_HOST_PATH:-$PWD}"   # host path of the deployment folder, set by compose
first_401=0

log() { echo "$(date -u +%FT%TZ) watchdog: $*"; }

http_status() {
  # busybox wget prints the status line to stderr with -S, also on errors
  wget -q -S -T 20 -O /dev/null --header "token: $TOKEN" "$API/token-details" 2>&1 \
    | grep -oE 'HTTP/[0-9.]+ [0-9]{3}' | tail -1 | awk '{print $2}'
}

decommission() {
  log "DECOMMISSION: site token rejected for ${AFTER_MIN} min - removing the VisionAI deployment"
  # exactly the images this deployment's containers run (inference, triton, models, watchdog)
  imgs="$(docker ps -a --filter label=com.docker.compose.project=visionai-edge --format '{{.Image}}' | sort -u | tr '\n' ' ')"
  log "images to remove: $imgs"
  docker stop -t 30 visionai-inference >/dev/null 2>&1
  if [ -d /host/visionai ]; then
    rm -rf /host/visionai/* /host/visionai/.[!.]* 2>/dev/null
    log "local data wiped"
  fi
  rm -f /host/repo/.env && log ".env removed"
  # A detached helper finishes the job after this container is gone: compose stops and
  # removes the project's containers (this one included), its volumes and its network;
  # then the images listed above, the GPU-check image and leftovers are removed.
  docker run -d --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$REPO_HOST_PATH:/host/repo:ro" \
    -w /host/repo "$SELF_IMAGE" sh -c \
    "sleep 3; docker compose -p visionai-edge down --volumes --remove-orphans; docker image rm -f $imgs nvidia/cuda:12.4.1-base-ubuntu22.04; docker image prune -f" >/dev/null
  log "done - compose removes the remaining pieces (containers, volume, network, images) in a few seconds"
  exit 0
}

[ -n "$TOKEN" ] || { log "VISIONAI_API_TOKEN empty, nothing to watch"; exec sleep infinity; }
log "watching $API/token-details every ${INTERVAL}s; decommission after ${AFTER_MIN} min of 401 (enabled=$ENABLED)"
while :; do
  code="$(http_status)"
  now=$(date +%s)
  case "$code" in
    200)
      [ "$first_401" != 0 ] && log "token accepted again, timer reset"
      [ -z "${ok_logged:-}" ] && { log "token accepted by the cloud (200)"; ok_logged=1; }
      first_401=0 ;;
    401)
      [ "$first_401" = 0 ] && { first_401=$now; log "token REJECTED (401) - decommission in ${AFTER_MIN} min unless it is accepted again"; }
      elapsed=$(( (now - first_401) / 60 ))
      log "token still rejected (${elapsed}/${AFTER_MIN} min)"
      if [ "$elapsed" -ge "$AFTER_MIN" ]; then
        [ "$ENABLED" = 1 ] && decommission || log "DECOMMISSION_ENABLED=0, not removing anything"
      fi ;;
    "") log "cloud unreachable, ignoring" ;;
    *)   log "unexpected HTTP $code, ignoring" ;;
  esac
  sleep "$INTERVAL"
done
