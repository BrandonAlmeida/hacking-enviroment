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
    Edite o arquivo `.env` e defina a variável de ambiente `WG_CONFIG` para o nome do arquivo que você deseja usar.
    ```bash
    WG_CONFIG=seu-arquivo-wireguard.conf # <-- Altere aqui
    ```

3.  **Configuração da Rede (Opcional)**:
    O range de IPs da rede Docker e os IPs estáticos dos contêineres são configurados através do arquivo `.env`. Por padrão, ele usa a rede `10.77.10.0/28`.

    Para personalizar o range, edite as seguintes variáveis no arquivo `.env`:

    ```bash
    NETWORK_SUBNET=10.77.10.0/28 # Defina aqui o CIDR da sua rede, ex: 192.168.50.0/24

    # IPs Estáticos dos Serviços
    # ATENÇÃO: Certifique-se de que estes IPs pertencem à NETWORK_SUBNET definida acima
    GATEWAY_IP=10.77.10.4   # IP do contêiner hacknet-gateway
    KALI_IP=10.77.10.2      # IP do contêiner kali-linux
    TOR_CLIENT_IP=10.77.10.6 # IP usado pelo Kali para rotear tráfego via Tor transparente
    ```
    **Importante**: Após alterar o `NETWORK_SUBNET`, você *deve* ajustar `GATEWAY_IP`, `KALI_IP` e `TOR_CLIENT_IP` para que estejam dentro do novo range da sub-rede.

4.  **Construa e Inicie o Ambiente**:
    Na raiz do projeto, execute:
    ```sh
    docker compose up -d --build
    ```
5. **Caso quiser, inicie apenas o container hacknet-gateway**
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

### Customização da Imagem Kali

No `Dockerfile.kali`, a instalação do pacote `kali-linux-default` foi comentada intencionalmente. Isso permite que você escolha se deseja uma instalação mínima do Kali (apenas com as ferramentas essenciais como `net-tools`, `git`, `curl`, etc.) ou uma instalação completa.

*   **Instalação Mínima (Padrão Atual)**: Se a linha permanecer comentada (`#kali-linux-default`), o contêiner Kali será construído com um conjunto menor de ferramentas, resultando em uma imagem menor e tempos de construção mais rápidos. Você pode instalar ferramentas específicas conforme a necessidade.
*   **Instalação Completa**: Para ter o conjunto completo de ferramentas padrão do Kali, descomente a linha `kali-linux-default` no `Dockerfile.kali`:

    ```dockerfile
    RUN apt update && apt install -y \
        kali-linux-default \
        net-tools iproute2 iputils-ping dnsutils \
        vim nano curl wget git zsh openssh-server \
        && apt clean
    ```
    Após modificar o `Dockerfile.kali`, lembre-se de reconstruir a imagem:
    ```bash
    docker compose build kali-linux
    ```

### Configurando um Tor Hidden Service (Serviço Oculto)

Você pode expor serviços rodando dentro de seus containers (por exemplo, um servidor SSH no Kali) como um Tor Hidden Service, tornando-os acessíveis apenas via rede Tor e sem revelar o IP de origem.

**Passos para configurar:**

1.  **Edite `gateway/tor/torrc`**:
    No arquivo `gateway/tor/torrc`, adicione as linhas de configuração `HiddenServiceDir` e `HiddenServicePort`. Um exemplo para expor a porta 22 (SSH) do container Kali (cujo IP é `10.77.10.2` por padrão) está comentado no próprio arquivo:

    ```ini
    # Exemplo de Tor Hidden Service:
    # Para expor a porta 22 (SSH) do container Kali (10.77.10.2) como um serviço oculto:
    #
    # HiddenServiceDir /var/lib/tor/hidden_service/kali_ssh/
    # HiddenServicePort 22 10.77.10.2:22
    #
    # O endereço .onion será gerado e salvo em /var/lib/tor/hidden_service/kali_ssh/hostname
    # O diretório /var/lib/tor/hidden_service/kali_ssh/ deve ter permissões 0700 e ser de propriedade do usuário "debian-tor".
    # Para persistir este serviço oculto, adicione um volume no docker-compose.yml:
    # - ./gateway/tor_hs_kali_ssh:/var/lib/tor/hidden_service/kali_ssh/
    ```
    **Lembre-se de descomentar as linhas `HiddenServiceDir` e `HiddenServicePort` para ativá-lo.**

2.  **Persistência do Serviço Oculto (Obrigatório)**:
    Para garantir que o seu endereço `.onion` não mude cada vez que o container `hacknet-gateway` for reiniciado, é **crucial** persistir o diretório `HiddenServiceDir` usando um volume Docker.

    Edite o seu `docker-compose.yml` e adicione um volume ao serviço `hacknet-gateway` (substitua `kali_ssh` pelo nome que você usou em `HiddenServiceDir`):

    ```yaml
    services:
      hacknet-gateway:
        # ...
        volumes:
          # ... outros volumes ...
          - ./gateway/tor_hs_kali_ssh:/var/lib/tor/hidden_service/kali_ssh/
    ```
    O diretório `./gateway/tor_hs_kali_ssh` será criado automaticamente no seu host e conterá os arquivos de chave e o `hostname` (o seu endereço `.onion`).

3.  **Reconstrua e Inicie**:
    Após as alterações, você precisará reconstruir o serviço `hacknet-gateway` e iniciá-lo:

    ```bash
    docker compose up -d --build hacknet-gateway
    ```
    Após a inicialização, o endereço `.onion` estará disponível no arquivo `gateway/tor_hs_kali_ssh/hostname` no seu host.

    **Nota**: Certifique-se de que o serviço que você está expondo (ex: `sshd` no Kali) esteja configurado para escutar na porta e interface corretas dentro do container. No Kali, o `sshd` geralmente escuta em `0.0.0.0:22` por padrão.
