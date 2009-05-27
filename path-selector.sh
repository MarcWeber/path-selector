#!/bin/sh
# GPL 2009
# Marc Weber based on a haskell app I wrote which was much more complicated :-)
# you can either run it as script or source it this way
# AS_LIB=1 . $PATH_TO_THIS_FILE

# BUGS - wont't fix: names containing \n is not supported
# BUGS to be fixed: See commented test cases

do_help(){
  local this_script=$(basename $0)
cat << EOF
  $this_script pat1 pat2 pat3

  $this_script is kind of xpath for directories/ files
  you should use it with cd, $EDITOR etc to be most productive

  pattern selector description:
  first char is "/" means set path2 to root

  The rest of the pattern selector is split by @ - , :
  @ : @foo expands to f*/o*/o* . This is default
  : : :foo expands to *f*o*o*
  = : regex match
  , : exact match or glob pattern. Examples:
      ,*.txt -> *.txt
      ,exact -> exact
  -nr : go to parent directory nr times
    -3 = ../../..

  + : append trailing path2 which doesn't exist yet
      eg /t+bar expands to /tmp/bar even if /tmp/bar doesn't exist
      (TODO reimplement this features)

  trailing / : match directories only

  Now you can put pieces together:
  /tt -> /tmp/this # file or directory
  /tt/ -> /tmp/this # directory only

  When beeing in /tmp/this:
    -2hm -> ../../home/m*

  etc

  Useful shell functions:

    C()   { cd       \$($this_script "\$@"); }
    E()   { \$EDITOR  \$($this_script "\$@"); }
    MDC() { mdc      \$($this_script "\$@"); }

  Instead of $this_script you can source $this_script by
  AS_LIB source $this_script 
  and use match as shown in main below.


  bug-reports, feedback to: marco-oweber@gmx.de
  updates: http://www.github.com/MarcWeber/path-selector
EOF
}

first_char(){
  if [ -n "$ZSH_VERSION" ]; then
    local a="$1"
    echo "${a[1]}" # ZSH
  else
    echo "${1:0:1}" # SH
  fi
}

# appends glob pattern to gglob
do_match(){
  local pattern="$1";
  shift 1

  [ -z "$pattern" ] && { echo "internal error"; exit 1; }

  echo "path2 : $path2; pattern :$pattern" 1>&2

  [ -d "$path2" ] || return

  # remove first char
  local real_pattern="${pattern#?}"

  # trailing / = match directories only
  [ -z "${pattern##*/}" ] && {
    local dirs_only=1
    pattern=${pattern/%\//}
  }
  local dir_and_files="${pattern##/}"

  local recurse="$1" # more params? recurse
  local extra_args=

  [ -n "$recurse" ] && get_dirs=1
  [ -n "$dir_and_files" ] && get_dirs=1
  [ -z "$dirs_only" ] && get_files=1
  
  local dirs=
  local files=

  local SED="sed -e /^\.$/d -e s@^\./@@" # remove leading ./

  [ "$(first_char "$pattern")" = "@" ] &&
    pattern="${pattern#?}" # remove @, because it's the default

  case "$pattern" in
    :*)
      # match if characters are found in this order. eg ab matches YYaZZZZZZZbXX
      local p="$( echo -n "*"; echo "$real_pattern" | sed 's/\(.\)/\1*/g')"
      gglob="${gglob}$p"
    ;;
    ,*)
      gglob="${gglob}${real_pattern}"
    ;;
    -*)
      # * levels up eg -3 = ../../..
      [ -n "$get_dirs"  ] && {
        for nr in `seq $real_pattern`; do
          dirs="${dirs}.."
        done
        gglob="${gglob}${dirs}"
      }
    ;;
    *) # @ = default, @ was stripped above
      local head="$(first_char "$pattern")"
      local tail="${pattern#?}"
      recurse="${tail}${recurse}"

      # repeat this step for the remaining chars
      [ -n "$tail" ] && extra_args="@$tail"

      set -x
      gglob="${gglob}${head}*"
    ;;
  esac
  if [ -n "$recurse" ]; then
    # recurse in to subdirs
    gglob="${gglob}/"
    if [ -z "$extra_args" ]; then
      do_match "$@"
    else
      do_match "$extra_args" "$@"
    fi
  fi
}

user_select(){
  local lines="$1" # get stdin
  [ -z "$lines" ] && return
  if [ $(echo -e "$lines" | wc -l) = 1 ]; then
    echo "$lines"
  else
    local nr=1
    echo "$lines" | while read match; do
      echo "$nr) $match" 1>&2
      nr=$(( $nr + 1 ))
    done
    read nr
    echo "$lines" | sed -n "${nr}p"
  fi
}

match(){
  local path2="$1"
  local pattern="$2"

  [ -z "$path2" ] && path2=./

  [ "${path2%/}" == "$path2" ] && path2="$path2/"

  [ "$(first_char "$pattern")" == "/" ] && {
    # jump to root if first char of pattern is /
    pattern="${pattern#?}"
    path2=/
  }
  
  # the parser: prepend '`' to each separator and use IFS to split by that
  local sep_by_back_tick="$(echo "$pattern" | sed 's/\([-=@,:+]\)/`\1/g')"
  IFS=\` read -a args <<< "$sep_by_back_tick"

  gglob= # global var
  do_match ${args[@]}
  echo "$gglob"
  # user_select "$lines"
}

self_test(){
  echo "FIXME"; exit 1 # Test is outdated
  # I don't test / prefix here
  t=$(mktemp -d); cd "$t"
  set -e -x
  # trap "echo cleaning up TMP $t; rm -fr '$t'" EXIT
  touch test1
  [ "$(set +x; match "$t" t; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t" ,*e*; set -x)" = $t/test1 ]

  # broken, why?
  # [ "$(set +x; match "$t" '=^test1$'; set -x)" = test1 ]

  [ "$(set +x; match "$t" ':t1'; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t" @t; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t" t; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t" t/; set -x)" = "" ]
  rm test1; mkdir test1
  [ "$(set +x; match "$t" @t/; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t" t/; set -x)" = $t/test1 ]
  [ "$(set +x; match "$t/test1" -1@t/; set -x)" = $t/test1/../test1 ]
  mkdir -p test2/foo
  #[ "$(set +x; match "$t/test1" ',**'; set -x)" = "
  #todd
  #" ]
  [ "$(set +x; match "$t" ":test2+testX/testY"; set -x)" = "$t/test2/testX/testY" ]
  echo "success"
}

# main
[ "$1" = "--help" ] && { do_help; exit; }
[ "$1" = "--self-test" ] && { self_test; exit; }
if [ -z "$AS_LIB" ]; then
  set -e
  for pattern in "$@"; do
    match "./" $pattern
  done
fi
