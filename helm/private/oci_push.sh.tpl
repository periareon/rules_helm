#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

{{BASH_RLOCATION_FUNCTION}}

runfiles_export_envvars

readonly CRANE="$(rlocation "{{crane_path}}")"
readonly LAYOUT_DIR="$(rlocation "{{layout_dir}}")"
readonly DIGEST_FILE="$(rlocation "{{digest_file}}")"
readonly TAGS_FILE="$(rlocation "{{tags_file}}")"
readonly IMAGE_PUSHERS_CSV="{{image_pushers}}"
readonly FIXED_ARGS=({{fixed_args}})

# set $@ to be FIXED_ARGS+$@
ALL_ARGS=(${FIXED_ARGS[@]+"${FIXED_ARGS[@]}"} $@)
if [[ ${#ALL_ARGS[@]} -gt 0 ]]; then
  set -- ${ALL_ARGS[@]}
fi

REPOSITORY=""
TAGS=()
GLOBAL_FLAGS=()
ARGS=()

while (( $# > 0 )); do
  case $1 in
    (--allow-nondistributable-artifacts|--insecure|-v|--verbose)
      GLOBAL_FLAGS+=( "$1" )
      shift;;
    (--platform)
      GLOBAL_FLAGS+=( "--platform" "$2" )
      shift; shift;;
    (-t|--tag)
      TAGS+=( "$2" )
      shift; shift;;
    (--tag=*)
      TAGS+=( "${1#--tag=}" )
      shift;;
    (-r|--repository)
      REPOSITORY="$2"
      shift; shift;;
    (--repository=*)
      REPOSITORY="${1#--repository=}"
      shift;;
    (*)
      ARGS+=( "$1" )
      shift;;
  esac
done

if [[ -z "${REPOSITORY}" ]]; then
  echo "ERROR: repository not set." >&2
  exit 1
fi

# Push container images first (chart references them by digest/tag)
if [[ -n "${IMAGE_PUSHERS_CSV}" ]]; then
  IFS=',' read -ra IMAGE_PUSHERS <<< "${IMAGE_PUSHERS_CSV}"
  for pusher_path in "${IMAGE_PUSHERS[@]}"; do
    pusher="$(rlocation "${pusher_path}")"
    echo "Pushing image: ${pusher_path}"
    "${pusher}"
  done
  echo "All images pushed successfully."
fi

# Read digest from build-time output (no jq needed)
DIGEST=$(cat "${DIGEST_FILE}")

echo "Pushing ${REPOSITORY}@${DIGEST}"

# Push by digest
REFS=$(mktemp)
"${CRANE}" push "${GLOBAL_FLAGS[@]+"${GLOBAL_FLAGS[@]}"}" "${LAYOUT_DIR}" "${REPOSITORY}@${DIGEST}" "${ARGS[@]+"${ARGS[@]}"}" --image-refs "${REFS}"

echo "Pushed: $(cat "${REFS}")"
echo "Digest: ${DIGEST}"

# Apply tags from file (version tag from chart metadata)
if [[ -e "${TAGS_FILE}" ]]; then
  while IFS= read -r tag || [[ -n "$tag" ]]; do
    [[ -z "$tag" ]] && continue
    "${CRANE}" tag "${GLOBAL_FLAGS[@]+"${GLOBAL_FLAGS[@]}"}" "$(cat "${REFS}")" "${tag}"
    echo "Tagged: ${REPOSITORY}:${tag}"
  done < "${TAGS_FILE}"
fi

# Apply tags from CLI
for tag in "${TAGS[@]+"${TAGS[@]}"}"
do
  "${CRANE}" tag "${GLOBAL_FLAGS[@]+"${GLOBAL_FLAGS[@]}"}" "$(cat "${REFS}")" "${tag}"
  echo "Tagged: ${REPOSITORY}:${tag}"
done
