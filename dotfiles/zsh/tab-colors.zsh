# Barva pozadí a emoji v názvu tabu podle adresáře (seznam v ~/.config/tab-colors)
typeset -g TAB_COLORS_FILE="$HOME/.config/tab-colors"

_tab_colors_apply() {
  local best="" color="" emoji="" dir col emo
  [[ -r $TAB_COLORS_FILE ]] || return
  while read -r dir col emo; do
    [[ -z $dir || $dir == \#* ]] && continue
    dir=${dir/#\~/$HOME}
    [[ ($PWD == $dir || $PWD == $dir/*) && ${#dir} -gt ${#best} ]] && { best=$dir; color=$col; emoji=$emo; }
  done < $TAB_COLORS_FILE
  [[ -n $color ]] && printf '\e]11;%s\a' $color || printf '\e]111\a'
  printf '\e]2;%s\a' "${emoji:+$emoji }${PWD/#$HOME/~}"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _tab_colors_apply
