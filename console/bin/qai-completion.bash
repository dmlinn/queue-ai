# shellcheck shell=bash
# source from ~/.zshrc or ~/.bashrc:
#   source /path/to/queue-ai/console/bin/qai-completion.bash
_qai() {
  local cur
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  if [ "${COMP_CWORD}" -eq 1 ]; then
    # shellcheck disable=SC2207
    COMPREPLY=($(compgen -W "help commands doctor ping ssh sleep wake dispatch status logs usage" -- "$cur"))
  fi
}
complete -F _qai qai 2>/dev/null || true
