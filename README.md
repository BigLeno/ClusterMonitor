# Guia de Monitoramento de Modelos Ollama com Notificações no Telegram

Este documento explica como configurar um monitor de modelos Ollama que envia notificações ao Telegram quando um modelo inicia ou para de rodar. Inclui passos para criar o script, configurar o serviço e garantir que tudo funcione automaticamente.

---

## 1. Requisitos

- Sistema Linux com suporte ao systemd.
- `curl` instalado.
- `ollama` instalado e acessível no caminho `/usr/local/bin/ollama`.
- Token do seu Bot Telegram.
- ID do chat no Telegram onde deseja receber as notificações.

---

## 2. Configuração do Script

### a. Obtenção do token do Telegram

Salve seu token, por exemplo:

```bash
TOKEN="SEU_TOKEN_AQUI"
```

### b. Caminho do `ollama`

Verifique o caminho do `ollama` com:

```bash
which ollama
```

Use caminho completo na variável `OLLAMA` no script.

### c. Script completo monitor.sh

Salve o seguinte conteúdo como `SEU/DIRETORIO`

```bash
#!/usr/bin/env bash
# =========================
# Script: monitor.sh
# Monitora modelos Ollama e notifica liga/desliga no Telegram
# =========================

# ——— Configurações ———
TOKEN="SEU_TOKEN_AQUI"
CHAT_ID="SEU_CHAT_ID_AQUI"
OLLAMA="/usr/local/bin/ollama"
STATE_FILE="/tmp/modelo_estado.txt"
LOG_FILE="/tmp/modelo_changes.log"

# ——— Informações do container (Proxmox LXC) ———
CT_NAME=$(hostname)
CT_ID=$(findmnt -n -o SOURCE / \
         | sed -En 's#.*(vm|subvol)-([0-9]+)-.*#\2#p')

# ——— Função para enviar mensagem ao Telegram ———
enviar_mensagem() {
  local texto="$1"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "parse_mode=Markdown" \
    --data-urlencode "text=${texto}" \
    > /dev/null 2>&1
}

# ——— Inicializa o STATE_FILE se não existir ———
if [ ! -f "$STATE_FILE" ]; then
  echo "parado:" > "$STATE_FILE"
fi

# ——— Loop de monitoramento ———
while true; do
  # 1) Captura a primeira linha útil do `ollama ps`
  saida=$($OLLAMA ps)
  linha=$(echo "$saida" | awk 'NR>1' | grep -v '^$' | head -n1)

  # 2) Define estado atual e extrai informações
  if [ -n "$linha" ]; then
    # Modelo ativo
    nome=$(echo "$linha" | awk '{print $1}')
    size=$(echo "$linha" | awk '{print $3" "$4}')
    processor=$(echo "$linha" | awk '{print $5" "$6}')
    until=$(echo "$linha" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i; print ""}' \
            | sed 's/ *$//')
    current_state="ativo"
    current_model="$nome"

    # Monta mensagem de ativação
    mensagem="🌟 Modelo ativo
📌 Nome: \`${nome}\`
📦 Size: \`${size}\`
⚙️ Processor: \`${processor}\`
⏳ Próximo término: \`${until}\`
🏷️ Container: \`${CT_NAME}\` (CTID: \`${CT_ID}\`)"
  else
    # Modelo parado
    current_state="parado"
    mensagem="❌ Modelo desligado
📌 Nome: \`${prev_model}\`
🏷️ Container: \`${CT_NAME}\` (CTID: \`${CT_ID}\`)"
    current_model=""
  fi

  # 3) Lê estado anterior do STATE_FILE
  prev_state=$(cut -d':' -f1  < "$STATE_FILE")
  prev_model=$(cut -d':' -f2- < "$STATE_FILE")

  # 4) Se mudou o estado, notifica e registra no log
  if [ "$current_state" != "$prev_state" ]; then
    enviar_mensagem "$mensagem"
    echo "${current_state}:${current_model}" > "$STATE_FILE"

    if [ "$current_state" = "ativo" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Ativado: ${current_model} (Size: ${size}, Processor: ${processor}, Until: ${until}, Container: ${CT_NAME}#${CT_ID})" \
        >> "$LOG_FILE"
    else
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Desligado: ${prev_model} (Container: ${CT_NAME}#${CT_ID})" \
        >> "$LOG_FILE"
    fi
  fi

  # 5) Aguarda antes de checar novamente
  sleep 30
done
```

Lembre-se de substituir ``SEU_TOKEN_AQUI`` e ``SEU_CHAT_ID_AQUI`` pelos seus valores.

## 3. Tornando o Script Executável


```bash
chmod +x /SEU/DIRETORIO/monitor.sh
```

## 4. Criando o Serviço Systemd
Crie o arquivo ``/etc/systemd/system/monitor-ollama.service`` com o seguinte conteúdo:

```bash
[Unit]
Description=Monitoramento de Modelos Ollama
After=network.target

[Service]
ExecStart=/SEU/DIRETORIO/monitor.sh
Restart=always
User=seu_usuario
Environment=PATH=/bin:/usr/bin:/usr/local/bin
WorkingDirectory=/SEU/DIRETORIO

[Install]
WantedBy=multi-user.target
```

### a. Ative e inicie o serviço:

```bash
sudo systemctl daemon-reload
sudo systemctl enable monitor-ollama
sudo systemctl start monitor-ollama
```

### b. Verifique o status:

```bash
sudo systemctl status monitor-ollama
```

Ele deve mostrar como ``active (running)``.

## 5. Reiniciando

A cada mudança no arquivo, você precisa fazer: 

```bash
chmod +x /SEU/DIRETORIO/monitor.sh
```

Em seguida:

```bash
sudo systemctl restart monitor-ollama
```

## 5. Como funciona

* O script verifica a saída de ``ollama ps`` a cada 30 segundos.
* Detecta mudança de estado (modelo iniciado ou parado).
* Envia uma mensagem formatada no Markdown ao Telegram.
* Não repete notificações, apenas quando há alteração de status.

## 6. Encerrando

Para parar o serviço:

```bash
sudo systemctl stop monitor-ollama
```

Para desabilitar na inicialização:

```bash
sudo systemctl disable monitor-ollama
```
