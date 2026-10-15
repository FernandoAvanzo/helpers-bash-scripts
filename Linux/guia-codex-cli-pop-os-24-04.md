# Guia passo a passo: instalar o Codex CLI no Pop!_OS 24.04

**Atualizado em:** 15 de outubro de 2026  
**Público:** estações de trabalho com Pop!_OS 24.04 LTS (Linux x86_64 ou ARM64)

## Objetivo

Este guia instala o Codex CLI, ferramenta de programação da OpenAI que funciona no terminal local. Você pode usá-la para entender um repositório, propor e editar código e executar tarefas de desenvolvimento. O Codex opera nos arquivos e comandos disponíveis no seu computador, portanto revise as permissões e as alterações propostas.

> Os comandos abaixo devem ser executados no terminal do Pop!_OS. Use uma conta de usuário comum; `sudo` só é usado para instalar pacotes do sistema.

## 1. Conferir o sistema e a arquitetura

Abra o Terminal e execute:

```bash
cat /etc/os-release
uname -m
```

Confirme que o sistema identifica Pop!_OS 24.04. `x86_64` indica Intel/AMD 64-bit; `aarch64` indica ARM64. O instalador oficial detecta a plataforma automaticamente.

## 2. Atualizar os pacotes do sistema

```bash
sudo apt update
sudo apt upgrade
```

Se houver atualização do kernel ou bibliotecas centrais, reinicie antes de prosseguir:

```bash
sudo reboot
```

## 3. Instalar pelo instalador oficial (recomendado)

O instalador oficial para Linux baixa o executável adequado e configura o Codex CLI no seu usuário:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

Se o comando `curl` não existir:

```bash
sudo apt install curl
```

Depois, execute novamente o instalador. Feche e reabra o terminal para atualizar o `PATH`, se necessário.

### Verificar a instalação

```bash
command -v codex
codex --version
```

O primeiro comando deve mostrar o caminho do executável e o segundo, a versão instalada.

## 4. Alternativa: instalar com npm

Use esta opção se já administra ferramentas JavaScript com Node.js e npm. Primeiro confira se ambos estão disponíveis:

```bash
node --version
npm --version
```

Se estiverem disponíveis, instale o pacote oficial:

```bash
npm install -g @openai/codex
```

Valide:

```bash
codex --version
```

Se aparecer erro de permissão no npm global, evite executar `sudo npm install -g`. Configure um prefixo npm no diretório do usuário ou use o instalador oficial da seção 3. Para configurar o prefixo do usuário:

```bash
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
printf '\nexport PATH="$HOME/.npm-global/bin:$PATH"\n' >> "$HOME/.profile"
source "$HOME/.profile"
npm install -g @openai/codex
```

## 5. Entrar na conta

Inicie o Codex:

```bash
codex
```

Na tela inicial, escolha **Sign in with ChatGPT** e conclua a autenticação no navegador. Use uma conta/plano com acesso ao Codex. Se o navegador não abrir automaticamente, siga o endereço e o código mostrados no terminal, quando disponíveis.

Também é possível autenticar com uma chave de API, caso sua organização prefira cobrança por API:

```bash
printenv OPENAI_API_KEY
```

Configure a chave apenas para a sessão atual:

```bash
export OPENAI_API_KEY="sua-chave"
codex
```

Não compartilhe a chave, não a coloque no histórico do shell e não a grave em arquivos versionados. A chave de API é faturada separadamente conforme o uso.

## 6. Usar o Codex em um projeto

Navegue até a pasta do projeto e inicie o CLI:

```bash
cd /caminho/para/seu/projeto
codex
```

Na primeira tarefa, peça uma ação específica, por exemplo: “Explique a estrutura deste projeto e identifique como executar os testes”. Leia as propostas com atenção e aprove apenas alterações ou comandos que você compreenda. Para projetos importantes, mantenha o código em Git e revise `git diff` antes de confirmar mudanças:

```bash
git status
 git diff
```

A interface oferece opções de aprovação e acesso ao ambiente. Prefira configurações restritas ao diretório de trabalho e a confirmação de comandos durante exploração. Os nomes e opções podem variar conforme a versão.

## 7. Repetir a instalação em outras estações

Em cada workstation Pop!_OS 24.04:

1. Atualize o sistema e verifique a arquitetura (etapas 1 e 2).
2. Execute o instalador oficial da etapa 3 ou siga a alternativa npm.
3. Confira `codex --version`.
4. Inicie `codex` e autentique a conta nessa máquina.
5. Entre na pasta de cada repositório e inicie uma sessão.

A instalação e os arquivos locais são por máquina/usuário. Não copie tokens, arquivos de autenticação ou a pasta de configuração entre máquinas. Faça login separadamente em cada estação. Para configurações compartilhadas, versione apenas arquivos de configuração não secretos e revise-os antes de usar.

## 8. Atualizar ou remover

Para a instalação npm:

```bash
npm update -g @openai/codex
```

O CLI também pode oferecer `codex --upgrade` conforme a modalidade de instalação. Confira a versão depois de atualizar:

```bash
codex --version
```

Para remover uma instalação feita pelo npm:

```bash
npm uninstall -g @openai/codex
```

Para o instalador standalone, consulte as instruções da versão instalada no repositório oficial; o caminho de desinstalação pode depender do instalador. Remover o executável não necessariamente apaga preferências e dados locais.

## 9. Solução de problemas

### `codex: command not found`

Reabra o terminal, verifique `command -v codex` e confira o `PATH`. Para instalação via npm, confirme que o diretório de binários npm está no `PATH`:

```bash
npm config get prefix
printf '%s\n' "$PATH"
```

### `curl: command not found`

```bash
sudo apt update && sudo apt install curl
```

### Erro de rede ou download

Verifique a conexão, proxy corporativo e políticas de firewall. A instalação standalone obtém componentes dos domínios de distribuição indicados no projeto oficial; peça à equipe de TI para permitir os destinos oficiais, se necessário. Como alternativa, use npm quando aprovado pela política da empresa.

### Problema de autenticação

Confirme que o navegador concluiu o fluxo com a conta correta, que a hora do sistema está correta e que a rede não bloqueia o login. Reinicie `codex` e tente novamente. Não envie tokens ou códigos de autenticação em chamados públicos.

### Verificações úteis

```bash
uname -m
command -v codex
codex --version
```

## Referências oficiais

- OpenAI Codex CLI - Getting Started: https://help.openai.com/en/articles/11096431
- Repositório oficial `openai/codex` e instruções de instalação: https://github.com/openai/codex
- Pacote oficial no npm: https://www.npmjs.com/package/@openai/codex
- Página oficial do Codex: https://chatgpt.com/codex

> Os comandos e métodos disponíveis podem mudar. Antes de padronizar a instalação da empresa, confira as instruções do repositório oficial e a política interna de software e credenciais.
