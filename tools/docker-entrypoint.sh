#!/usr/bin/env bash
set -euo pipefail

write_gradle_proxy() {
  local proxy_url="${HTTPS_PROXY:-${HTTP_PROXY:-}}"
  local no_proxy="${NO_PROXY:-${no_proxy:-localhost,127.0.0.1,::1}}"

  mkdir -p /root/.gradle

  if [[ -z "${proxy_url}" ]]; then
    return 0
  fi

  local without_scheme="${proxy_url#*://}"
  local authority="${without_scheme%%/*}"
  local credentials=""
  local host_port="${authority}"

  if [[ "${authority}" == *"@"* ]]; then
    credentials="${authority%@*}"
    host_port="${authority#*@}"
  fi

  local host="${host_port%:*}"
  local port="${host_port##*:}"

  if [[ -z "${host}" || -z "${port}" || "${host}" == "${port}" ]]; then
    return 0
  fi

  local non_proxy_hosts
  non_proxy_hosts="$(printf '%s' "${no_proxy}" | sed 's/,/|/g')"

  {
    printf 'systemProp.http.proxyHost=%s\n' "${host}"
    printf 'systemProp.http.proxyPort=%s\n' "${port}"
    printf 'systemProp.https.proxyHost=%s\n' "${host}"
    printf 'systemProp.https.proxyPort=%s\n' "${port}"
    printf 'systemProp.http.nonProxyHosts=%s\n' "${non_proxy_hosts}"
    printf 'systemProp.https.nonProxyHosts=%s\n' "${non_proxy_hosts}"

    if [[ -n "${credentials}" && "${credentials}" == *":"* ]]; then
      printf 'systemProp.http.proxyUser=%s\n' "${credentials%%:*}"
      printf 'systemProp.http.proxyPassword=%s\n' "${credentials#*:}"
      printf 'systemProp.https.proxyUser=%s\n' "${credentials%%:*}"
      printf 'systemProp.https.proxyPassword=%s\n' "${credentials#*:}"
    fi
  } > /root/.gradle/gradle.properties
}

write_gradle_proxy
exec "$@"
