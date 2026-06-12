#!/usr/bin/env bash
# feed_parity — gera tools/feed_parity/snapshot.json via PostgREST (lado client
# do harness). Alternativa ao fetch_snapshot.sql (Studio) que não passa dados
# por chat/console: tudo vai direto pra arquivo local (gitignored).
#
# SEGURANÇA: SERVICE_ROLE só via ambiente; nunca impresso, nunca em argv.
#   export SERVICE_ROLE=$(supabase projects api-keys --project-ref gaxfmniffjvwrwyunorl -o json \
#     | jq -r '.[] | select(.name=="service_role") | .api_key')
#   bash tools/feed_parity/fetch_snapshot.sh
#   unset SERVICE_ROLE
set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:-https://gaxfmniffjvwrwyunorl.supabase.co}"
OUT="$(dirname "$0")/snapshot.json"
USERS=(
  a91e0ed2-4ca2-4239-9758-11a78e39b17c
  b7226e54-0913-4824-9459-55fc4b686c8a
  456ea636-f298-404c-9097-6c3ae62f7175
  1d052e97-ce50-4373-9170-747c01ad3681
  16835f3d-f30e-40db-8842-da111921a085
  d466f487-60e7-4ef2-a523-83f43aa99f01
  c5bdb3ac-c587-4bbd-a714-34468fc81fea
)

command -v jq >/dev/null 2>&1 || { echo "ERRO: jq não encontrado."; exit 1; }
: "${SERVICE_ROLE:?ERRO: export SERVICE_ROLE=<service-role-key> antes de rodar}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

api() { # api <path-com-query> <arquivo> [range]
  if [ -n "${3:-}" ]; then
    curl -sSf "$SUPABASE_URL/rest/v1/$1" \
      -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" \
      -H "Range: $3" > "$2"
  else
    curl -sSf "$SUPABASE_URL/rest/v1/$1" \
      -H "apikey: $SERVICE_ROLE" -H "Authorization: Bearer $SERVICE_ROLE" > "$2"
  fi
}

in_list=$(IFS=,; echo "${USERS[*]}")

api "jobs?is_active=eq.true&select=id,area,work_model,job_type,location_city,location_state,salary_min,deadline&order=id" "$tmp/jobs.json"
api "profile_desired_titles?user_id=in.($in_list)&select=user_id,title" "$tmp/titles.json"
api "profile_job_preferences?user_id=in.($in_list)&select=user_id,primary_location_city,work_mode,job_types" "$tmp/jps.json"
api "profile_other_locations?user_id=in.($in_list)&select=user_id,city" "$tmp/locs.json"

# swipes podem passar do db-max-rows (1000) — pagina por Range até esvaziar
: > "$tmp/swipes_all.json"; echo '[]' > "$tmp/swipes_all.json"
page=0
while :; do
  from=$((page * 1000)); to=$((from + 999))
  api "swipe_actions?user_id=in.($in_list)&select=user_id,job_id&order=created_at,job_id" \
      "$tmp/swipes_page.json" "$from-$to"
  n=$(jq 'length' "$tmp/swipes_page.json")
  jq -s '.[0] + .[1]' "$tmp/swipes_all.json" "$tmp/swipes_page.json" > "$tmp/swipes_merged.json"
  mv "$tmp/swipes_merged.json" "$tmp/swipes_all.json"
  [ "$n" -lt 1000 ] && break
  page=$((page + 1))
  [ "$page" -gt 50 ] && { echo "ERRO: paginação de swipes não converge"; exit 1; }
done

users_json=$(printf '%s\n' "${USERS[@]}" | jq -R . | jq -s .)

jq -n \
  --slurpfile jobs "$tmp/jobs.json" \
  --slurpfile titles "$tmp/titles.json" \
  --slurpfile jps "$tmp/jps.json" \
  --slurpfile locs "$tmp/locs.json" \
  --slurpfile swipes "$tmp/swipes_all.json" \
  --argjson users "$users_json" '
  {fetched_at: (now | todate),
   jobs: $jobs[0],
   users: [ $users[] as $u |
     {user_id: $u,
      desired_titles: [ $titles[0][] | select(.user_id == $u) | .title ],
      job_preferences: (([ $jps[0][] | select(.user_id == $u)
                           | {primary_location_city, work_mode, job_types} ] | first) // null),
      other_locations: [ $locs[0][] | select(.user_id == $u) | .city ],
      swiped_job_ids:  [ $swipes[0][] | select(.user_id == $u) | .job_id ]} ]}' \
  > "$OUT"

echo "snapshot: $OUT"
jq -r '"jobs=\(.jobs|length) users=\(.users|length) swipes=\([.users[].swiped_job_ids|length]|add)"' "$OUT"
