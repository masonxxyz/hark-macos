if [ -z "${ZSH_VERSION:-}" ]; then
    echo "dev.sh requires zsh; run 'source dev.sh' from zsh." >&2
    return 1 2>/dev/null || exit 1
fi

_root_dir=$(dirname $(greadlink -f $0))

source "$_root_dir/devutils/shared.sh"
source "$_root_dir/devutils/set_quilt_vars.sh"

___hark_setup_presetup() {
    local download=true
    if [ $# -eq 1 ] && [ "$1" = -c ]; then
        download=false
    elif [ $# -ne 0 ]; then
        echo "usage: hark setup|presetup [-c]" >&2
        return 1
    fi

    if [ -d "$_src_dir/out" ]; then
        echo "$_src_dir/out already exists" >&2
        return
    fi

    rm -rf "$_src_dir" && mkdir -p "$_src_dir"

    fetch_sources "$download"
    mkdir -p "$_out_dir"
    cd "$_src_dir"
    python3 "$_main_repo/utils/prune_binaries.py" --keep-build-dependencies "$_src_dir" "$_main_repo/pruning.list"
    hark_resources
    write_gn_args "$_arch" dev

    python3 "$_main_repo/utils/hark_version.py" \
        --tree "$_main_repo" \
        --platform-tree "$_root_dir" \
        --chromium-tree "$_src_dir"
}

___hark_setup() {
    ___hark_setup_presetup "$@"

    "$_root_dir/devutils/update_patches.sh" merge

    cd "$_src_dir"
    quilt push -a --refresh

    gn_gen --export-compile-commands
}

___hark_reset() {
    "$_root_dir/devutils/update_patches.sh" unmerge || true
    rm "$_subs_cache" || true
    rm "$_namesubs_cache" || true
    if mv "$_src_dir" "${_src_dir}x"; then
        rm -rf "${_src_dir}x" &
    fi
}

___hark_name_substitution() {
    if [ "$1" = "nameunsub" ]; then
        python3 "$_main_repo/utils/name_substitution.py" --unsub \
            -t "$_src_dir" --backup-path "$_namesubs_cache"
    elif [ "$1" = "namesub" ]; then
        if [ -f "$_namesubs_cache" ]; then
            echo "$_namesubs_cache exists, are you sure you want to do this?" >&2
            echo "if yes, then delete the $_namesubs_cache file" >&2
            return
        fi

        python3 "$_main_repo/utils/name_substitution.py" --sub \
            -t "$_src_dir" --backup-path "$_namesubs_cache"
    else
        echo "unknown action: $1" >&2
        return
    fi
}

___hark_apply_translations() {
    python3 "$_main_repo/utils/i18n_apply.py" -t "$_src_dir"
}

___hark_generate_translations() {
    python3 "$_main_repo/devutils/i18n.py" generate
}

___hark_substitution() {
    if [ "$1" = "unsub" ]; then
        python3 "$_main_repo/utils/domain_substitution.py" revert \
            -c "$_subs_cache" "$_src_dir"

        ___hark_name_substitution nameunsub
    elif [ "$1" = "sub" ]; then
        if [ -f "$_subs_cache" ]; then
            echo "$_subs_cache exists, are you sure you want to do this?" >&2
            echo "if yes, then delete the $_subs_cache file" >&2
            return
        fi

        ___hark_name_substitution namesub

        python3 "$_main_repo/utils/domain_substitution.py" apply \
            -r "$_main_repo/domain_regex.list" \
            -f "$_main_repo/domain_substitution.list" \
            -c "$_subs_cache" \
            "$_src_dir"
    else
        echo "unknown action: $1" >&2
        return
    fi
}

___hark_build() {
    local -a siso_flags=(${=SISO_FLAGS:-})
    cd "$_src_dir"
    if [ -n "${SISO_REAPI_ADDRESS:-}" ]; then
        configure_siso || return
    fi
    hark_build -k 0 "${siso_flags[@]}" "$@"
}

___hark_run() {
    local profile="$HOME/Library/Application Support/com.cognify.hark.dev"
    # .git is a file in linked worktrees, and a directory in the main checkout
    if [ -f "$_root_dir/.git" ]; then
        profile="$profile.wt/${_root_dir#*.wt/}"
    fi

    "$_out_dir/Hark.app/Contents/MacOS/Hark" \
    --user-data-dir="$profile" \
    --enable-ui-devtools \
    --use-mock-keychain \
    --disable-features=DialMediaRouteProvider \
    "$@"
}

___hark_wt_path() {
    local common
    common=$(git -C "$_root_dir" rev-parse --path-format=absolute --git-common-dir)
    echo "${common:h}.wt/$1"
}

___hark_wt_new() {
    local name=${1:?usage: hark wt new <name>} dest
    dest=$(___hark_wt_path "$name")
    if [ ! -f "$_root_dir/patches/series.merged" ] || [ ! -d "$_src_dir/.pc" ]; then
        echo "$_src_dir must be set up with merged patches applied" >&2
        return 1
    fi

    if git -C "$_root_dir" rev-parse -q --verify "refs/heads/$name" >/dev/null \
        || git -C "$_main_repo" rev-parse -q --verify "refs/heads/$name" >/dev/null; then
        echo "branch $name already exists" >&2
        return 1
    fi

    git -C "$_root_dir" worktree add -b "$name" "$dest" HEAD
    git -C "$_main_repo" worktree add -b "$name" "$dest/hark-chromium" HEAD

    git -C "$_root_dir" diff --binary HEAD -- . ":!patches" ":!hark-chromium" \
        | git -C "$dest" apply --allow-empty
    git -C "$_main_repo" diff --binary HEAD -- . ":!patches" \
        | git -C "$dest/hark-chromium" apply --allow-empty

    rm -rf "$dest/patches"
    /bin/cp -c -R "$_root_dir/patches" "$dest/patches"

    mkdir -p "$dest/build"
    ln -s "${_download_cache:A}" "$dest/build/download_cache"
    /bin/cp -c -R -p "$_src_dir" "$dest/build/src"
    for f in "$_subs_cache" "$_namesubs_cache"; do
        [ ! -f "$f" ] || /bin/cp -c -p "$f" "$dest/build/"
    done

    printf '%s\n' "$dest/patches" > "$dest/build/src/.pc/.quilt_patches"
    (cd "$dest" && source ./dev.sh && hark configure)
}

___hark_wt_rm() {
    local dest
    dest=$(___hark_wt_path "${1:?usage: hark wt rm <name>}")
    [ -f "$dest/.git" ] || { echo "$dest is not a worktree" >&2; return 1; }
    rm -rf "$dest/build"
    git -C "$_main_repo" worktree remove --force "$dest/hark-chromium" || true
    git -C "$_root_dir" worktree remove --force "$dest"
}

___hark_wt() {
    case "${1:-}" in
        new) shift; ___hark_wt_new "$@";;
        rm) shift; ___hark_wt_rm "$@";;
        ls) git -C "$_root_dir" worktree list;;
        *)
            echo "usage: hark wt <new <name>|rm <name>|ls>" >&2
            return 1
    esac
}

___hark_pull() {
    if [ -f "$_subs_cache" ]; then
        echo "source files are substituted, please run 'hark unsub' first" >&2
        return 1
    fi

    cd "$_src_dir" && quilt pop -a || true
    "$_root_dir/devutils/update_patches.sh" unmerge || true

    for dir in "$_root_dir" "$_main_repo"; do
        git -C "$dir" stash \
        && git -C "$dir" fetch \
        && git -C "$dir" rebase origin/main \
        && git -C "$dir" stash pop \
        || true
    done

    "$_root_dir/devutils/update_patches.sh" merge
    cd "$_src_dir" && quilt push -a --refresh
}

___hark_patches_merge() {
    "$_root_dir/devutils/update_patches.sh" merge
}

___hark_patches_unmerge() {
    "$_root_dir/devutils/update_patches.sh" unmerge
}

___hark_quilt_push() {
    cd "$_src_dir" && quilt push -a --refresh
}

___hark_quilt_pop() {
    cd "$_src_dir" && quilt pop -a
}

___hark_validate() {
    if [ "$1" = "config" ]; then
        python3 "$_main_repo/devutils/validate_config.py"
    elif [ "$1" = "patches" ]; then
        if [ ! -f "patches/series.merged" ]; then
            echo "patches/series.merged doesn't exist. did you forget to merge?" >&2
            return 1
        fi
        python3 "$_main_repo/devutils/validate_patches.py" \
            -l "$_src_dir" \
            -s patches/series.merged
    elif [ "$1" = "series" ]; then
        "$_root_dir/devutils/check_patch_files.sh"
    else
        echo "unknown validate action. usage: hark validate <config|patches|series>" >&2
    fi
}

___hark_format() {
    cd "$_src_dir"
    quilt diff | "$_src_dir/third_party/clang-format/script/clang-format-diff.py" \
    -p1 -i -style=file
}

___hark_find_tidy_diff() {
    if [ -n "$_tidy_diff_script" ]; then
        return
    elif command -v clang-tidy-diff >/dev/null 2>&1; then
        _tidy_diff_script=$(command -v clang-tidy-diff)
    elif command -v clang-tidy-diff.py >/dev/null 2>&1; then
        _tidy_diff_script=$(command -v clang-tidy-diff.py)
    else
        _tidy_diff_script=$(find /opt/homebrew/Cellar/llvm -name clang-tidy-diff.py | head -1)
    fi

    if [ -z "$_tidy_diff_script" ]; then
        echo "could not find clang-tidy-diff.py script." >&2
        echo "ensure that you have llvm installed on your system" >&2
        return 1
    fi
}

___hark_strip_compile_commands() {
    _ccmd_path="$_out_dir/compile_commands.json"
    [ "$_ccmd_stripped" = 1 ] && return;
    _ccmd_stripped=1

    echo "normalizing compile_commands.json, this will take a while..."
    cp "$_ccmd_path" "$_ccmd_path.orig";
    gsed -Ei 's/^(\s*"command": ").*?\s(\S+bin\/clang)/\1\2/g' "$_ccmd_path"
}

___hark_tidy() {
    ___hark_find_tidy_diff || return;
    ___hark_strip_compile_commands;
    quilt diff | "$_tidy_diff_script" \
        -regex '.*\.(cc|mm)' \
        -use-color \
        -p1 \
        -path "$_out_dir" \
        -quiet \
        -j$(nproc)
}

___hark_lint() {
    ___hark_format;
    ___hark_tidy;
}

___hark_menu() {
    set -e
    case $1 in
        setup) shift; ___hark_setup "$@";;
        presetup) shift; ___hark_setup_presetup "$@";;
        configure) gn_gen --export-compile-commands;;
        resources) hark_resources;;

        sub|unsub) ___hark_substitution "$1";;
        namesub|nameunsub) ___hark_name_substitution "$1";;
        translate) ___hark_apply_translations;;
        transgen) ___hark_generate_translations;;

        merge) ___hark_patches_merge;;
        unmerge) ___hark_patches_unmerge;;
        push) ___hark_quilt_push;;
        pop) ___hark_quilt_pop;;
        pull) ___hark_pull;;

        validate) ___hark_validate "$2";;
        format) ___hark_format;;
        tidy) ___hark_tidy;;
        lint) ___hark_lint;;

        build) shift; ___hark_build "$@";;
        run) shift; ___hark_run "$@";;
        reset) ___hark_reset;;
        wt) shift; ___hark_wt "$@";;
        *)
            echo "usage: hark <command>" >&2
            echo "\tsetup [-c] - sets up the dev environment, optionally cloning Chromium" >&2
            echo "\t         equivalent of: [presetup, merge, push, configure]" >&2
            echo "\tpresetup [-c] - prepares sources and dependencies, optionally cloning Chromium" >&2
            echo "\tconfigure - generates build configuration and tools" >&2
            echo "\tresources - generates and copies hark resources (such as icons)" >&2

            echo "\n" >&2
            echo "\tsub - apply google domain and name substitutions" >&2
            echo "\tunsub - undo google domain and name substitutions" >&2
            echo "\tnamesub - apply only name substitutions" >&2
            echo "\tnameunsub - undo only name substitutions" >&2
            echo "\ttranslate - apply translations from i18n directory" >&2
            echo "\ttransgen - generate source strings for translation" >&2

            echo "\n" >&2
            echo "\tmerge - merges all patches" >&2
            echo "\tunmerge - unmerges all patches" >&2
            echo "\tpush - applies all patches" >&2
            echo "\tpop - undoes all patches" >&2
            echo "\tpull - undoes all patches, pulls from git, redoes all patches" >&2

            echo "\n" >&2
            echo "\tvalidate config - validates the build configuration" >&2
            echo "\tvalidate patches - validates that patches are applied correctly" >&2
            echo "\tvalidate series - checks the consistency of the series file" >&2
            echo "\tformat - formats the topmost patch according to Chromium coding style" >&2
            echo "\ttidy - runs clang-tidy on the topmost patch" >&2
            echo "\tlint - hark format + hark tidy" >&2

            echo "\n" >&2
            echo "\tbuild - builds a development binary" >&2
            echo "\trun [args] - runs a development build of hark with dev data dir & ui devtools enabled" >&2
            echo "\treset - nukes everything" >&2

            echo "\n" >&2
            echo "\twt new <name> - creates a worktree with an APFS clone of the current source tree" >&2
            echo "\twt rm <name> - removes a worktree and its source tree, keeping its branches" >&2
            echo "\twt ls - lists worktrees" >&2
    esac
}

hark() {
    (___hark_menu "$@")
}

if ! (return 0 2>/dev/null); then
    printf "usage:\n\t$ source dev.sh\n\t$ hark\n" 2>&1
    exit 1
else
    if [ "$__hark_loaded" = "" ]; then
        __hark_loaded=1
        PS1="📯 $PS1"
    fi
fi
