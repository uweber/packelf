#!/bin/bash
set -eo pipefail

if [ "$1" == "-c" ]; then
    export cache_dir="$2"
    shift
    shift
fi

[ $# -lt 2 ] && {
    echo "usage: $0 [-c <CACHE_DIR>] <ELF_SRC_PATH> <DST_PATH> [ADDITIONAL_LIBS ...]"
    echo " -c    cache extracted binaries in given directory"
    exit 1
}

src="$1"
dst="$2"
shift
shift

libs="$(ldd "$src" | grep -F '/' | sed -E 's|[^/]*/([^ ]+).*?|/\1|')"
ld_so="$(echo "$libs" | grep -F '/ld-linux-')"
export ld_so="$(basename "$ld_so")"
export program="$(basename "$src")"

envsubst '$program $ld_so $cache_dir' >"$dst" <<- 'EOF'
	#!/usr/bin/env sh
	cache_dir="$cache_dir"
	if [ -n "$cache_dir" ]; then
	    tmp_dir="$cache_dir/static-$program"
	    mkdir -p "$tmp_dir"
	else
	    tmp_dir="$(mktemp -d)"
	    check_path="$tmp_dir/__check_permission__"
	    trap 'rm -rf $tmp_dir' 0 1 2 3 6
	    if ! (touch "$check_path" && chmod +x "$check_path" && [ -x "$check_path" ]); then
	        rm -rf "$tmp_dir"
	        tmp_dir="$(TMPDIR="$(pwd)" mktemp -d)"
	    fi
	fi
	if [ ! -e "$tmp_dir/$program" ]; then
	    sed '1,/^#__END__$/d' "$0" | tar -xz -C "$tmp_dir"
	    sed -i 's@/etc/ld.so.preload@/etc/___so.preload@g' "$tmp_dir/$ld_so"
	fi
	"$tmp_dir/$ld_so" --library-path "$tmp_dir" "$tmp_dir/$program" "$@"
	exit $?
	#__END__
EOF

tar -czh --transform 's/.*\///g' "$src" $libs "$@" >>"$dst" 2> >(grep -v 'Removing leading' >&2)
chmod +x "$dst"
