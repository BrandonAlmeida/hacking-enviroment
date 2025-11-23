#!/bin/bash
set -e

# Executa a configuração de rede única para garantir que o padrão seja VPN
echo "[Entrypoint] Configurando a rota de rede padrão para a VPN..."
/usr/local/bin/switch_net.sh --vpn

# Executa o comando principal passado para o contêiner (por exemplo, /bin/zsh)
exec "$@"
