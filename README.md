# Hackingnet Environment

## Visão Geral

Este projeto cria um ambiente de pentesting seguro e modular usando Docker. A arquitetura é projetada para garantir que todo o tráfego direcionado ao container hacknet-gateway (1080 - VPN WIREGUARD ou 9050 - TOR) seja roteado através de um gateway seguro, que utiliza uma VPN WireGuard e pode, opcionalmente, rotear o tráfego através da rede Tor para uma camada adicional de anonimato.

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

- **Cliente**: Um ambiente `kalilinux/kali-rolling` padrão com as ferramentas mais comuns ou qualquer software que tenha suporte ao proxy socks5.
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
4. **Caso quiser, inicie apenas o container hacknet-gateway**
   Na raiz do projeto, execute:
   ```sh
    docker compose up -d --build hacknet-gateway
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
curl https://icanhazip.com
# Deverá mostrar o IP do servidor VPN
```

#### **Modo Tor**
Roteia todo o tráfego através da VPN e, em seguida, pela rede Tor.
```sh
sudo /usr/local/bin/switch_net.sh --tor
```
**Verificação:**
```sh
curl https://icanhazip.com
# Deverá mostrar o IP de um nó de saída da rede Tor
```
O script funciona alterando o endereço de IP de origem dos pacotes do contêiner Kali. O gateway identifica esse IP de origem especial e redireciona o tráfego para o proxy transparente do Tor.

---
### Gerenciando o Roteamento diretamente no Host via Proxy:
**Navegador:**
No seu navegador de preferência, configure o proxy Socks5 com direcionamento do trafego para o container hacknet-gateway.   
Ex:
- 127.0.0.1:1080 (Saida pela VPN Wireguard)
- 127.0.0.1:9050 (Saida pela rede TOR [TOR OVER VPN])

**Outras ferramentas**   
Qualquer ferramenta que tenha a capacidade de direcionar o trafego de rede via proxy SOCKS5 pode ser utilizada em conjunto com o container hacknet-gateway.   
Ex:    
VPN:
```sh
curl --proxy socks5h://127.0.0.1:1080 https://icanhazip.com
```
TOR:
```sh
curl --proxy socks5h://127.0.0.1:9050 https://icanhazip.com
```
OBS:   
- A mesma lógica se aplica a configuração de proxy via navegador (firefox, chrome, edge, etc...)
- Funciona também via [proxychains](https://www.pyproxy.com/information/how-to-configure-socks5-proxy-via-proxychains.html)
  
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
