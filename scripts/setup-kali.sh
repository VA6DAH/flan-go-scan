#!/usr/bin/env bash
# Install Podman, Podman Desktop, and Flan on Kali.
# Run as the kali user (not root): bash setup-kali.sh
# Optional: TOGETHER_API_KEY=... bash setup-kali.sh
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
  echo "Run this as the kali user with sudo, not as root." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y podman git uidmap slirp4netns fuse-overlayfs flatpak curl

if ! grep -q "^${USER}:" /etc/subuid; then
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "${USER}"
  echo "Added subordinate IDs. Log out and log back in, then re-run this script." >&2
  exit 1
fi

flatpak remote-add --if-not-exists --user flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install -y --user flathub io.podman_desktop.PodmanDesktop

REPO="${HOME}/flan-go-scan"
if [[ ! -d ${REPO}/.git ]]; then
  git clone https://github.com/VA6DAH/flan-go-scan.git "${REPO}"
fi
cd "${REPO}"
git fetch origin
git checkout main
git pull --ff-only origin main

podman build -t localhost/flan:latest .
podman volume exists flan-reports || podman volume create flan-reports

if [[ -n ${TOGETHER_API_KEY:-} ]]; then
  podman secret exists together_api_key && podman secret rm together_api_key
  podman secret create --env together_api_key TOGETHER_API_KEY
fi

MARKER="# flan podman wrapper"
if ! grep -Fq "${MARKER}" "${HOME}/.bashrc"; then
  cat >> "${HOME}/.bashrc" <<'EOF'

# flan podman wrapper
flan() {
  extra=()
  if podman secret exists together_api_key; then
    extra+=(--secret together_api_key,type=env,target=TOGETHER_API_KEY)
  fi
  podman run --rm "${extra[@]}" -v flan-reports:/work:U -w /work localhost/flan:latest "$@"
}
EOF
fi

podman run --rm -v flan-reports:/work:U -w /work localhost/flan:latest --help >/dev/null
echo "Podman $(podman --version)"
echo "Flan image: localhost/flan:latest"
echo "New shell, then: flan -t scanme.nmap.org"
echo "Desktop: flatpak run io.podman_desktop.PodmanDesktop"
echo "Together key: TOGETHER_API_KEY=... podman secret create --env together_api_key TOGETHER_API_KEY"
