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
