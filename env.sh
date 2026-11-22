# The architecture of the running shell
# Also used to determine the build target architecture
_arch="$(/usr/bin/uname -m)"

# General paths
_root_dir=${_root_dir:-$(dirname "$(greadlink -f "$0")")}
_download_cache="$_root_dir/build/download_cache"
_src_dir="$_root_dir/build/src"
_out_dir="$_src_dir/out/Default"
_main_repo="$_root_dir/hark-chromium"
_subs_cache="$_root_dir/build/subs.tar.gz"
_namesubs_cache="$_root_dir/build/namesubs.tar"

# Build tool paths
_depot_tools_dir="$_src_dir/third_party/depot_tools"
_siso_path="$_src_dir/third_party/siso/cipd/siso"
_gn_path="$_src_dir/buildtools/mac/gn"

# Local conveniences: use a full Xcode even if xcode-select points at the
# Command Line Tools, and prefer a repo-local Python venv (.venv) if present.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ] \
    && [ "$(xcode-select -p 2>/dev/null)" = /Library/Developer/CommandLineTools ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if [ -x "$_root_dir/.venv/bin/python3" ]; then
    case ":$PATH:" in
        *":$_root_dir/.venv/bin:"*) ;;
        *) export PATH="$_root_dir/.venv/bin:$PATH" ;;
    esac
fi
