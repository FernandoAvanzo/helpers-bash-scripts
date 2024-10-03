#Homebrew things
export PATH="/opt/homebrew/bin:$PATH"
export PATH="/opt/homebrew/sbin:$PATH"

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(autojump git vscode alias-finder fzf zsh-autosuggestions zsh-better-npm-completion ag aliases colored-man-pages docker dirhistory)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

#NU Things
eval "$(pyenv init --path)"
source $HOME/.nurc
# BEGIN ANSIBLE MANAGED BLOCK - NU_HOME ENV
export NU_HOME="$HOME/dev/nu"
export NUCLI_HOME=$NU_HOME/nucli
export PATH="$NUCLI_HOME:$PATH"
# END ANSIBLE MANAGED BLOCK - NU_HOME ENV
# BEGIN ANSIBLE MANAGED BLOCK - GO
export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"
# END ANSIBLE MANAGED BLOCK - GO
# BEGIN ANSIBLE MANAGED BLOCK - NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && . "$(brew --prefix)/opt/nvm/nvm.sh"
# END ANSIBLE MANAGED BLOCK - NVM
# BEGIN ANSIBLE MANAGED BLOCK - ANDROID SDK
export ANDROID_HOME="/Users/fernando.avanzo/Library/Android/sdk"
export ANDROID_SDK="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
# END ANSIBLE MANAGED BLOCK - ANDROID SDK
# BEGIN ANSIBLE MANAGED BLOCK - RBENV
eval "$(rbenv init -)"
# END ANSIBLE MANAGED BLOCK - RBENV
# BEGIN ANSIBLE MANAGED BLOCK - MOBILE MONOREPO
export MONOREPO_ROOT="${NU_HOME}/mini-meta-repo"
export PATH="$PATH:$MONOREPO_ROOT/monocli/bin"
# END ANSIBLE MANAGED BLOCK - MOBILE MONOREPO
# BEGIN ANSIBLE MANAGED BLOCK - Flutter SDK
export FLUTTER_SDK_HOME="$HOME/sdk-flutter"
export FLUTTER_ROOT="$FLUTTER_SDK_HOME"
export PATH="$PATH:$FLUTTER_SDK_HOME/bin:$HOME/.pub-cache/bin:$FLUTTER_ROOT/bin/cache/dart-sdk/bin"
# END ANSIBLE MANAGED BLOCK - Flutter SDK
# Nucli autocomplete
source "$NU_HOME/nucli/nu.bashcompletion"

# Modify Bash Prompt
export EDITOR=/usr/bin/vim
export LC_CTYPE='en_US.UTF-8'

#that things if not work you can remove
PROMPT="%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"
PROMPT+=' %{$fg[cyan]%}%(5~|%-1~/.../%3~|%~)%{$reset_color%} $(git_prompt_info)'

# GPG
export GPG_TTY=$(tty)
export PINENTRY_USER_DATA="USE_CURSES=1"

# MY SCRATCH FOLDER
export SCRATCH=/Users/fernando.avanzo/Library/Application\ Support/JetBrains/IntelliJIdea2024.1/scratches

# Git branch in prompt.
parse_git_branch() {
 while read -r branch; do
     [[ $branch = \** ]] && current_branch=${branch#* }
 done < <(git branch 2>/dev/null)

 [[ $current_branch ]] && printf ' [%s]' "$current_branch"
}
export NU_HOME=${HOME}/dev/nu
export NUCLI_HOME=${NU_HOME}/nucli
export PATH=${NUCLI_HOME}:${PATH}

# SCALA Configuration
export SCALA_HOME=/Users/fernando.avanzo/Library/Application\ Support/Coursier/bin
export PATH="${HOME}/.jenv/bin:${PATH}"
   eval "$(jenv init -)"

# Setting Clojure and Leiningen Configuration
export PATH="/usr/local/bin/clojure:/usr/local/bin/gpg:${PATH}"
