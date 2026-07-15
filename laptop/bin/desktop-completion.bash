# shellcheck shell=bash
# source from ~/.zshrc or ~/.bashrc:
#   source /path/to/desktop-runner/laptop/bin/desktop-completion.bash
_desktop() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [ "${COMP_CWORD}" -eq 1 ]; then
    # shellcheck disable=SC2207
    COMPREPLY=($(compgen -W "help commands doctor ping ssh sleep wake dispatch status logs usage" -- "$cur"))
  fi
}
complete -F _desktop desktop 2>/dev/null || true
