#!/usr/bin/env bash
# Instala o Monitor: serviço de usuário (systemd) + widget do KDE Plasma 6.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${PYTHON:-$(command -v python3 || true)}"

if [[ -z "$PYTHON" ]]; then
  echo "python3 não encontrado." >&2
  exit 1
fi

if ! "$PYTHON" -c "import psutil" >/dev/null 2>&1; then
  echo "psutil não instalado. Rode:" >&2
  echo "  $PYTHON -m pip install -r \"$ROOT/requirements.txt\"" >&2
  exit 1
fi

# --- widget do Plasma -------------------------------------------------------
if command -v kpackagetool6 >/dev/null 2>&1; then
  if kpackagetool6 --type Plasma/Applet --install "$ROOT/plasmoid" >/dev/null 2>&1; then
    echo "Widget instalado."
  elif kpackagetool6 --type Plasma/Applet --upgrade "$ROOT/plasmoid" >/dev/null 2>&1; then
    echo "Widget atualizado."
  else
    echo "Não consegui instalar o widget (é preciso KDE Plasma 6)." >&2
  fi
else
  echo "kpackagetool6 não encontrado; widget ignorado."
fi

# --- serviço systemd de usuário --------------------------------------------
if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  mkdir -p "$UNIT_DIR"

  cat > "$UNIT_DIR/monitor.service" <<EOF
[Unit]
Description=Monitor local (CPU, RAM e GPU)
After=network-online.target

[Service]
Type=simple
WorkingDirectory=$ROOT
ExecStart=$PYTHON -u server.py
Restart=always
RestartSec=2
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable monitor.service
  systemctl --user restart monitor.service
  echo "Serviço ativo: http://localhost:8787"
else
  echo "systemd de usuário indisponível. Rode manualmente:"
  echo "  $PYTHON \"$ROOT/server.py\""
fi

echo
echo "Widget: clique com o botão direito na área de trabalho → Adicionar widgets → Monitor."
