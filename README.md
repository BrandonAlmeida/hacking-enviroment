# Hackingnet Environment

## Visão Geral

Este projeto cria um ambiente de pentesting seguro e modular usando Docker. A arquitetura é projetada para garantir que todo o tráfego da estação de trabalho Kali Linux seja roteado através de um gateway seguro, que utiliza uma VPN WireGuard e pode, opcionalmente, rotear o tráfego através da rede Tor para uma camada adicional de anonimato.

Um firewall robusto com funcionalidade "Kill Switch" está implementado para prevenir qualquer vazamento de IP caso a conexão VPN falhe.

## Arquitetura

O fluxo de tráfego é gerenciado da seguinte forma:

**Modo VPN (Padrão):**
```
[Kali Container] -> [Gateway] -> [Túnel WireGuard] -> [Internet]
```

**Modo Tor (Opcional):**
```
[Kali Container] -> [Gateway] -> [Túnel WireGuard] -> [Rede Tor] -> [Internet]
```

---

## Funcionalidades

- **Cliente Kali Linux**: Um ambiente `kalilinux/kali-rolling` padrão com as ferramentas mais comuns.
- **Gateway WireGuard**: Todo o tráfego de saída é forçado a passar por um túnel WireGuard.
- **Tor-over-VPN**: Um mecanismo simples para rotear todo o tráfego do Kali através da rede Tor, já dentro do túnel VPN.
- **Firewall & Kill Switch**: Políticas de `iptables` garantem que nenhum pacote saia para a internet se a VPN não estiver ativa.
- **Proxies SOCKS5**: O gateway expõe proxies para o host acessar a rede através da VPN ou do Tor diretamente.
  - **VPN (Dante):** `socks5h://127.0.0.1:1080`
  - **Tor:** `socks5h://127.0.0.1:9050`

---

## Guia Rápido (Quick Start)

1.  **Adicione suas Configurações WireGuard**:
    Coloque seus arquivos de configuração `.conf` do WireGuard no diretório `gateway/wireguard/`.

2.  **Selecione a Configuração VPN**:
    Edite o arquivo `docker-compose.yml` e defina a variável de ambiente `WG_CONFIG` no serviço `hacknet-gateway` para o nome do arquivo que você deseja usar.
    ```yaml
    services:
      hacknet-gateway:
        ...
        environment:
          - WG_CONFIG=seu-arquivo-wireguard.conf # <-- Altere aqui
    ```

3.  **Construa e Inicie o Ambiente**:
    Na raiz do projeto, execute:
    ```sh
    docker compose up -d --build
    ```

---

## Como Usar

### Acessando o Contêiner Kali

Para entrar no terminal da estação de trabalho Kali, execute:
```sh
docker exec -it kali-linux /bin/zsh
```

### Gerenciando o Roteamento (Dentro do Kali)

O script `switch_net.sh` permite alternar facilmente entre os modos de roteamento. **É necessário executá-lo como root (`sudo`)**.

#### **Modo VPN (Padrão)**
Roteia todo o tráfego apenas através da VPN WireGuard. Este é o modo padrão ao iniciar o contêiner.
```sh
sudo /usr/local/bin/switch_net.sh --vpn
```
**Verificação:**
```sh
curl ipinfo.io/ip
# Deverá mostrar o IP do servidor VPN
```

#### **Modo Tor**
Roteia todo o tráfego através da VPN e, em seguida, pela rede Tor.
```sh
sudo /usr/local/bin/switch_net.sh --tor
```
**Verificação:**
```sh
curl ipinfo.io/ip
# Deverá mostrar o IP de um nó de saída da rede Tor
```
O script funciona alterando o endereço de IP de origem dos pacotes do contêiner Kali. O gateway identifica esse IP de origem especial e redireciona o tráfego para o proxy transparente do Tor.

---

## Para Desenvolvedores

### Estrutura do Projeto

- `docker-compose.yml`: Orquestra os serviços `kali-linux` e `hacknet-gateway`.
- `gateway/start.sh`: O script principal do gateway. Configura o firewall (kill switch), WireGuard, NAT, Tor e Dante.
- `kali/switch_net.sh`: Script executado no cliente Kali para alternar entre os modos de roteamento (`--vpn` ou `--tor`).
- `kali/entrypoint.sh`: Ponto de entrada do contêiner Kali, define a rota padrão inicial.

### Convenções de Código

- **Scripts Shell**: Manter `set -euo pipefail`, indentação de 4 espaços e blocos de código funcional.
- **Dockerfiles**: Agrupar blocos `RUN` e documentar flags importantes como `privileged` e `cap_add`.
- **Commits**: Seguir o padrão `type: description` (ex: `feat: add tor routing mode`, `fix: correct firewall rule`).
