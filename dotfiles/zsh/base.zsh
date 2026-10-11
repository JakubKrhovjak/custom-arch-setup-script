# Základ zsh (dřív /usr/share/zsh/manjaro-zsh-config): volby, doplňování, klávesy, pluginy z repozitáře extra.

## Volby
setopt correct              # oprava překlepů v příkazech
setopt extendedglob
setopt nocaseglob
setopt rcexpandparam
setopt nocheckjobs
setopt numericglobsort
setopt nobeep
setopt appendhistory
setopt histignorealldups
setopt autocd               # samotná cesta = cd
setopt inc_append_history
setopt histignorespace      # příkaz začínající mezerou se neukládá do historie

HISTFILE=~/.zhistory
HISTSIZE=10000
SAVEHIST=10000
WORDCHARS=${WORDCHARS//\/[&.;]}

## Doplňování (zsh-completions se načte samo ze site-functions)
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' rehash true
zstyle ':completion:*' menu select
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
autoload -U compinit colors zcalc
compinit -d ~/.zcompdump
colors

## Klávesy
bindkey -e
bindkey '^[[7~' beginning-of-line
bindkey '^[[H' beginning-of-line
[[ -n "${terminfo[khome]}" ]] && bindkey "${terminfo[khome]}" beginning-of-line
bindkey '^[[8~' end-of-line
bindkey '^[[F' end-of-line
[[ -n "${terminfo[kend]}" ]] && bindkey "${terminfo[kend]}" end-of-line
bindkey '^[[2~' overwrite-mode
bindkey '^[[3~' delete-char
bindkey '^[[C' forward-char
bindkey '^[[D' backward-char
bindkey '^[[5~' history-beginning-search-backward
bindkey '^[[6~' history-beginning-search-forward
bindkey '^[Oc' forward-word
bindkey '^[Od' backward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^H' backward-kill-word       # Ctrl+Backspace
bindkey '^[[Z' undo                   # Shift+Tab

## Aliasy
alias cp="cp -i"
alias df='df -h'
alias free='free -m'
alias gitu='git add . && git commit && git push'
eval "$(dircolors -b)"
alias ls='ls --color=auto'

## Barevné manuálové stránky
export LESS_TERMCAP_mb=$'\E[01;32m'
export LESS_TERMCAP_md=$'\E[01;32m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;47;34m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;36m'
export LESS=-R

## Titulek okna a aktuální adresář pro terminál (OSC 7 → nová karta v Konsoli ve stejném adresáři)
autoload -U add-zsh-hook
function setTermTitle { print -Pn "\e]2;%n@%m:%~\a" }
function setTermTitleCmd { print -Pn "\e]2;${1:gs/%/%%}\a" }
function reportCwd { print -n "\e]7;file://${HOST}${PWD// /%20}\a" }
add-zsh-hook precmd setTermTitle
add-zsh-hook precmd reportCwd
add-zsh-hook preexec setTermTitleCmd

## Pluginy (pořadí: našeptávání, zvýraznění, hledání v historii až po zvýraznění)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
zmodload zsh/terminfo
bindkey "$terminfo[kcuu1]" history-substring-search-up
bindkey "$terminfo[kcud1]" history-substring-search-down
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
