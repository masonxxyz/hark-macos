#!/bin/bash -eux

_root_dir="$(dirname "$(greadlink -f "$0")")"
_main_repo="$_root_dir/hark-chromium"

_hark_version=$(python3 "$_main_repo/utils/hark_version.py" --tree "$_main_repo" --platform-tree "$_root_dir" --print)

_file_name_base="hark_${_hark_version}"
_x64_file_name="${_file_name_base}_x86_64-macos.dmg"
_arm64_file_name="${_file_name_base}_arm64-macos.dmg"

echo "x64_file_name=$_x64_file_name" >> $GITHUB_OUTPUT
echo "arm64_file_name=$_arm64_file_name" >> $GITHUB_OUTPUT
echo "release_tag_version=$_hark_version" >> $GITHUB_OUTPUT
echo "release_name=$_hark_version" >> $GITHUB_OUTPUT
