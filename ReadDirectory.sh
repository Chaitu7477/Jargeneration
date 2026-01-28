#!/usr/bin/env bash
set -euo pipefail

BRANCH="${1:-main}"
JARS_DIR="${2:-}"   # Fabric/<AppName>/Apps/_JARs

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_URL="https://gitlab.com/muchbetter-group/groups/maveric-systems-temenos/digital_banking_fabric_source/ti/localservices.git"

TMP_DIR="${ROOT}/.ls-tmp"
DST_ROOT="${ROOT}/localservices"
DST_JAVA="${DST_ROOT}/Fabric/java"
DST_MODULES="${DST_JAVA}/modules"

echo "current path is ${ROOT}"
echo "Preparing sources for jars under: ${JARS_DIR}"

# --- Clone or refresh consolidated source repo into a temp area ---
rm -rf "${TMP_DIR}"
git clone --branch "${BRANCH}" --depth 1 "${REPO_URL}" "${TMP_DIR}"
echo "Repo cloned to ${TMP_DIR}"

# --- Work out which artifactIds we need from the app's _JARs ---
declare -a ART_IDS=()
if [[ -d "${JARS_DIR}" ]]; then
  # 1) from file name:  <artifactId>-<version>.jar  -> artifactId
  while IFS= read -r J; do
    base="$(basename "$J" .jar)"
    # strip version-ish tails: -1.2.3, -1.2.3-SNAPSHOT, -20240101.123456-1 etc.
    aid="$(sed -E 's/-([0-9]+(\.[0-9A-Za-z_-]+)*)($|[-.].*)$//' <<<"${base}")"
    ART_IDS+=("${aid}")
  done < <(find "${JARS_DIR}" -maxdepth 1 -type f -name '*.jar' | sort)

  # 2) also try manifest Implementation-Title (fallbacks)
  while IFS= read -r J; do
    title="$(unzip -p "$J" META-INF/MANIFEST.MF 2>/dev/null | awk -F': ' '/^Implementation-Title:/ {print $2; exit}')"
    [[ -n "${title:-}" ]] && ART_IDS+=("${title}")
  done < <(find "${JARS_DIR}" -maxdepth 1 -type f -name '*.jar' | sort)
fi

# Unique & non-empty
mapfile -t ART_IDS < <(printf '%s\n' "${ART_IDS[@]:-}" | sed '/^$/d' | sort -u)

if [[ "${#ART_IDS[@]}" -eq 0 ]]; then
  echo "WARN: No jars detected in ${JARS_DIR}. Building full Fabric/java if present."
fi

# --- Stage destination structure ---
rm -rf "${DST_JAVA}"
mkdir -p "${DST_MODULES}"

# Fast path: if repo has a parent pom at Fabric/java/pom.xml, copy it whole
if [[ -f "${TMP_DIR}/Fabric/java/pom.xml" && "${#ART_IDS[@]}" -eq 0 ]]; then
  echo "Copying entire Fabric/java tree (no specific jars detected)..."
  rsync -a --delete "${TMP_DIR}/Fabric/java/" "${DST_JAVA}/"
else
  echo "Selecting modules for artifactIds:"
  printf ' - %s\n' "${ART_IDS[@]:-<none>}"

  # Collect (pomPath, artifactId, moduleDir)
  declare -A MOD_DIRS=()

  # Find all pom.xml and match artifactIds
  while IFS= read -r POM; do
    ART=$(sed -n 's:.*<artifactId>\(.*\)</artifactId>.*:\1:p' "$POM" | head -1)
    [[ -z "${ART}" ]] && continue
    for A in "${ART_IDS[@]:-}"; do
      if [[ "${ART}" == "${A}" ]]; then
        SRC_DIR="$(cd "$(dirname "$POM")" && pwd)"
        MOD_DIRS["$ART"]="${SRC_DIR}"
        break
      fi
    done
  done < <(find "${TMP_DIR}" -type f -name pom.xml)

  if [[ "${#MOD_DIRS[@]}" -eq 0 ]]; then
    echo "No matching modules found for detected JARs. Copying entire Fabric/java if available."
    if [[ -f "${TMP_DIR}/Fabric/java/pom.xml" ]]; then
      rsync -a --delete "${TMP_DIR}/Fabric/java/" "${DST_JAVA}/"
    else
      # As a last resort copy the full repo (your existing build may rely on it)
      rsync -a --delete "${TMP_DIR}/" "${DST_ROOT}/"
      exit 0
    fi
  else
    # Copy only matched modules into modules/<artifactId>
    for ART in "${!MOD_DIRS[@]}"; do
      SRC="${MOD_DIRS[$ART]}"
      echo "Staging module ${ART}"
      rsync -a "${SRC}/" "${DST_MODULES}/${ART}/"
    done

    # Create an aggregator POM under Fabric/java that includes staged modules
    cat > "${DST_JAVA}/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.fabric.localservices</groupId>
  <artifactId>localservices-parent</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <modules>
EOF

    for ART in "${!MOD_DIRS[@]}"; do
      echo "    <module>modules/${ART}</module>" >> "${DST_JAVA}/pom.xml"
    done

    cat >> "${DST_JAVA}/pom.xml" <<'EOF'
  </modules>
</project>
EOF

  fi
fi

echo "Prepared Maven sources at: ${DST_JAVA}"
find "${DST_JAVA}" -maxdepth 3 -name pom.xml -print | sed 's/^/ - /'