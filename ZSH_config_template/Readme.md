# ZSH Personal Configuration

### Instalatios Steps Commands

```bash
    sudo apt install zsh-syntax-highlighting
```

```bash
    echo "source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" >> ~/.zshrc
```

```bash
    sh -c "$(wget https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh -O -)"
```

```bash
    man git
```

```bash
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

```bash
    git clone https://github.com/lukechilds/zsh-better-npm-completion ~/.oh-my-zsh/custom/plugins/zsh-better-npm-completion
```

```bash
    curl -L git.io/antigen > antigen.zsh
```

```bash
    git clone https://github.com/wting/autojump.git
```

```bash
    cd autojump
    ./install.py or ./uninstall.py
```

```bash
    #Please manually add the following line(s) to ~/.zshrc:

	[[ -s /home/fernandoavanzo/.autojump/etc/profile.d/autojump.sh ]] && source /home/fernandoavanzo/.autojump/etc/profile.d/autojump.sh

	autoload -U compinit && compinit -u

    #Please restart terminal(s) before running autojump.
```

```bash
    git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin
```

```bash
    git clone --depth 1 https://github.com/unixorn/fzf-zsh-plugin.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-zsh-plugin
```

```bash
    plugins=(git
             colored-man-pages
             vscode
             alias-finder
             fzf-zsh-plugin
             zsh-autosuggestions
             zsh-better-npm-completion
             aliases
             docker
             dirhistory
             gradle
             ubuntu)
```

### References
- [My Notion Instalando e Configurando o ZSH ](https://www.notion.so/fernando-avanzo/Instalando-e-Configurando-o-ZSH-no-Ubuntu-20-04-by-Augusto-Ribeiro-Guto-Medium-bf0565d74b88449b8868783de63027aa?pvs=4)
- [My Notion zsh-autosuggestions/INSTALL.md ](https://www.notion.so/fernando-avanzo/zsh-autosuggestions-INSTALL-md-at-master-zsh-users-zsh-autosuggestions-b855e68b289e4faf81469532d0b5b57a?pvs=4)
