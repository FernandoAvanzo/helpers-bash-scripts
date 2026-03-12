#!/bin/bash

# ==============================================================================
# Script de Instalação do Notion (Repackaged) para Pop!_OS 24.04
# ==============================================================================

set -e  # Encerra o script se algum comando falhar

# Cores para saída
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # Sem cor

echo -e "${GREEN}Iniciando verificação do sistema...${NC}"

# 1. Verificar se é root (necessário para instalar pacotes)
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script deve ser executado com sudo.${NC}"
   exit 1
fi

# 2. Atualizar base de pacotes e instalar pré-requisitos
echo -e "${GREEN}Verificando e instalando dependências (wget, curl, gdebi)...${NC}"
apt update
apt install -y wget curl gdebi-core

# 3. Obter a URL da versão mais recente (.deb) do GitHub
echo -e "${GREEN}Buscando a versão mais recente no GitHub...${NC}"
REPO="notion-enhancer/notion-repackaged"
# Busca o link do asset que termina em .deb para x86_64
LATEST_DEB_URL=$(curl -s https://api.github.com \

    | grep "browser_download_url.*deb" \
    | grep "amd64" \
    | cut -d '"' -f 4 | head -n 1)

if [ -z "$LATEST_DEB_URL" ]; then
    echo -e "${RED}Erro: Não foi possível encontrar o arquivo .deb no GitHub.${NC}"
    exit 1
fi

# 4. Download do pacote
TEMP_DEB="/tmp/notion-desktop.deb"
echo -e "${GREEN}Baixando pacote de: $LATEST_DEB_URL${NC}"
wget -O "$TEMP_DEB" "$LATEST_DEB_URL"

# 5. Instalação do .deb
echo -e "${GREEN}Instalando o Notion...${NC}"
gdebi -n "$TEMP_DEB"

# 6. Verificação final
echo -e "${GREEN}Validando instalação...${NC}"
if command -v notion-app &> /dev/null || command -v notion-app-enhanced &> /dev/null; then
    echo -e "${GREEN}====================================================${NC}"
    echo -e "${GREEN}SUCESSO: Notion instalado corretamente!${NC}"
    echo -e "Você já pode encontrá-lo no seu menu de aplicativos."
    echo -e "${GREEN}====================================================${NC}"
else
    echo -e "${RED}ERRO: A instalação parece ter falhado. Verifique os logs acima.${NC}"
    exit 1
fi

# Limpeza
rm "$TEMP_DEB"

