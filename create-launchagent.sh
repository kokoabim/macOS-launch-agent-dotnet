#!/usr/bin/env bash

set -eo pipefail

script_name="${0##*/}"
script_title="Create macOS Launch Agent from Template"
script_version="1.0"

script_options="t:"
script_switches="hoyz"

function usage() {
    end "$script_title v${script_version}
Usage: $script_name [-$script_switches] [-$script_options $(text_underline value)] <$(text_underline org)> <$(text_underline project)> <$(text_underline name)> <$(text_underline title)> <$(text_underline parent_dir)> <$(text_underline deploy_dir)>

$(text_underline Arguments:)
 $(text_underline deploy_dir)  Base directory where launch agents are deployed (must be absolute, e.g. /opt/example)
 $(text_underline name)        Launch agent name (must be a valid C# class name, e.g. FooBar)
 $(text_underline title)       Launch agent title (must be a valid string, e.g. \"My Launch Agent\")
 $(text_underline org)         Organization identifier (must be a valid reverse domain, e.g. com.example, net.example)
 $(text_underline parent_dir)  Parent directory to create the launch agent project directory within
 $(text_underline project)     Project name (must be a valid C# project name, e.g. MyNamespace.FooBar)

$(text_underline Options:)
 -t <source>  Template source directory (default: current directory)

$(text_underline Switches:)
 -h  Show this help
 -o  Overwrite target project directory (if exists)
 -y  Confirm yes to run
 -z  Dry-run (no changes made; commands printed)
" 0
}

function end() {
    local e=$? || :
    set +e
    trap - EXIT SIGHUP SIGINT SIGQUIT SIGTERM

    local end_message="$1"
    local end_code=${2:-$e}

    if [[ "$end_message" != "" ]]; then
        if [ "$end_code" -ne 0 ]; then
            text_red "$script_name" >&2
            echo -n ": " >&2
        fi
        echo "$end_message" >&2
    fi

    exit "$end_code"
}

trap end EXIT SIGHUP SIGINT SIGQUIT SIGTERM

function text_ansi() {
    local code=$1
    shift
    echo -en "\033[${code}m$*\033[0m"
}
function text_blue() { text_ansi 34 "$@"; }
function text_bold() { text_ansi 1 "$@"; }
function text_green() { text_ansi 32 "$@"; }
function text_italic() { text_ansi 3 "$@"; }
function text_light() { text_ansi 2 "$@"; }
function text_red() { text_ansi 31 "$@"; }
function text_underline() { text_ansi 4 "$@"; }
function text_yellow() { text_ansi 33 "$@"; }

function json_raw_value() { echo -n "$1" | jq -cr "$2 // empty" 2>/dev/null; }
function json_value() { echo -n "$1" | jq -c "$2 // empty" 2>/dev/null; }

function verify_use() {
    set -eo pipefail

    if ! which jq &>/dev/null; then
        end "Not installed or in PATH: jq" 1
    fi

    if [[ "$platform" == "unknown" ]]; then
        end "Unknown platform" 1
    fi
}

function read_json_config() {
    set -eo pipefail

    if [[ ! -f "$json_config_path" ]]; then
        end "Configuration file not found: $json_config_path" 1
    fi

    json_config=$(<"$json_config_path")
    if [[ -z "$json_config" ]]; then
        end "Configuration file is empty: $json_config_path" 1
    fi
}

function confirm_run() {
    [[ ${yes:-false} == true ]] && return

    read -r -p "${1:-Continue}? [y/N] " -n 1
    [[ $REPLY == "" ]] && echo -en "\033[1A" >&2
    echo >&2
    [[ $REPLY =~ ^[Yy]$ ]] || end "" 0
}

function copy_directories() {
    set -eo pipefail

    local copyDirectoriesLength
    local copyDirectories
    local src_dir
    local dest_dir
    copyDirectoriesLength=$(jq -r '.copyDirectories | length' "$json_config_path")

    if [[ $copyDirectoriesLength -eq 0 ]]; then
        text_yellow "[CopyDirectory] No directories to copy\n"
        return
    else
        text_green "[CopyDirectory] Copying ${copyDirectoriesLength} directories...\n"
    fi

    copyDirectories=$(jq -r '.copyDirectories[]' "$json_config_path" | tr -d '\r')

    for dir in $copyDirectories; do
        src_dir="$template_source_dir/$dir"
        dest_dir="$project_dir/$dir"

        if [[ ! -d "$src_dir" ]]; then
            text_red "[CopyDirectory] Directory not found: $src_dir\n"
            continue
        fi

        $dry_run cp -R "$src_dir" "$dest_dir" || text_red "[CopyDirectory] Failed to copy directory: $src_dir to $dest_dir\n"
    done
}

function copy_files() {
    set -eo pipefail

    local copyFilesLength
    local copyFiles
    local src_file
    local dest_file

    copyFilesLength=$(jq -r '.copyFiles | length' "$json_config_path")
    if [[ $copyFilesLength -eq 0 ]]; then
        text_yellow "[CopyFile] No files to copy\n"
        return
    else
        text_green "[CopyFile] Copying ${copyFilesLength} files...\n"
    fi

    copyFiles=$(jq -r '.copyFiles[]' "$json_config_path" | tr -d '\r')

    for file in $copyFiles; do
        src_file="$template_source_dir/$file"
        dest_file="$project_dir/$file"

        if [[ ! -f "$src_file" ]]; then
            text_red "[CopyFile] File not found: $src_file\n"
            continue
        fi

        $dry_run cp "$src_file" "$dest_file" || text_red "[CopyFile] Failed to copy file: $src_file to $dest_file\n"
    done
}

function replace_in_files() {
    set -eo pipefail
    shopt -s extglob || end "Failed to enable extglob" 1
    shopt -s globstar || end "Failed to enable globstar" 1

    local replaceInFilesLength
    local replaceInFile
    local src_file
    local src_files
    local pattern
    local replacement

    replaceInFilesLength=$(jq -r '.replaceInFiles | length' "$json_config_path")

    if [[ $replaceInFilesLength -eq 0 ]]; then
        text_yellow "[ReplaceInFile] No files to replace text in\n"
        return
    else
        text_green "[ReplaceInFile] Replacing text in ${replaceInFilesLength} files...\n"
    fi

    for ((i = 0; i < replaceInFilesLength; i++)); do
        replaceInFile=$(jq -r ".replaceInFiles[$i]" "$json_config_path")
        src_file="$project_dir/$(json_raw_value "$replaceInFile" '.src')"
        pattern=$(json_raw_value "$replaceInFile" '.pattern')
        replacement=$(json_raw_value "$replaceInFile" '.replacement')

        replacement=$(expand_placeholders "$replacement")

        if [[ "$dry_run" == "" ]] && [[ "$src_file" =~ \* ]]; then
            pushd "$project_dir" >/dev/null
            src_files=$(eval echo "$src_file")
            popd >/dev/null

            if [[ "$src_files" == "$src_file" ]]; then
                text_red "[ReplaceInFile] No files found matching pattern: $src_file\n"
                continue
            fi
        else
            src_files="$src_file"
        fi

        for src_file in $src_files; do
            if [[ "$dry_run" == "" ]] && [[ ! -f "$src_file" ]]; then
                text_red "[ReplaceInFile] File not found: $src_file\n"
                continue
            fi

            if [[ "$platform" == "macos" ]]; then
                $dry_run sed -i '' -e "s/$pattern/$replacement/g" "$src_file" || text_red "[ReplaceInFile] Failed to replace text in file: $src_file\n"
            else
                $dry_run sed -i -e "s/$pattern/$replacement/g" "$src_file" || text_red "[ReplaceInFile] Failed to replace text in file: $src_file\n"
            fi
        done
    done
}

function rename_files() {
    set -eo pipefail

    local renameFilesLength
    local renameFile
    local src_file
    local dest_file

    renameFilesLength=$(jq -r '.renameFiles | length' "$json_config_path")

    if [[ $renameFilesLength -eq 0 ]]; then
        text_yellow "[RenameFile] No files to rename\n"
        return
    else
        text_green "[RenameFile] Renaming ${renameFilesLength} files...\n"
    fi

    for ((i = 0; i < renameFilesLength; i++)); do
        renameFile=$(jq -r ".renameFiles[$i]" "$json_config_path")

        src_file="$project_dir/$(json_raw_value "$renameFile" '.src')"
        dest_file="$project_dir/$(json_raw_value "$renameFile" '.dest')"

        dest_file=$(expand_placeholders "$dest_file")

        if [[ "$dry_run" == "" ]] && [[ ! -f "$src_file" ]]; then
            text_red "[RenameFile] File not found: $src_file\n"
            continue
        fi

        $dry_run mv "$src_file" "$dest_file" || text_red "[RenameFile] Failed to rename file: $src_file to $dest_file\n"
    done
}

function rename_directories() {
    set -eo pipefail

    local renameDirectoriesLength
    local renameDirectory
    local src_dir
    local dest_dir

    renameDirectoriesLength=$(jq -r '.renameDirectories | length' "$json_config_path")

    if [[ $renameDirectoriesLength -eq 0 ]]; then
        text_yellow "[RenameDirectory] No directories to rename\n"
        return
    else
        text_green "[RenameDirectory] Renaming ${renameDirectoriesLength} directories...\n"
    fi

    for ((i = 0; i < renameDirectoriesLength; i++)); do
        renameDirectory=$(jq -r ".renameDirectories[$i]" "$json_config_path")

        src_dir="$project_dir/$(json_raw_value "$renameDirectory" '.src')"
        dest_dir="$project_dir/$(json_raw_value "$renameDirectory" '.dest')"

        dest_dir=$(expand_placeholders "$dest_dir")

        if [[ "$dry_run" == "" ]] && [[ ! -d "$src_dir" ]]; then
            text_red "[RenameDirectory] Directory not found: $src_dir\n"
            continue
        fi

        $dry_run mv "$src_dir" "$dest_dir" || text_red "[RenameDirectory] Failed to rename directory: $src_dir to $dest_dir\n"
    done
}

function delete_directories() {
    set -eo pipefail

    local deleteDirectoriesLength
    local deleteDirectory
    local dir_to_delete

    deleteDirectoriesLength=$(jq -r '.deleteDirectories | length' "$json_config_path")

    if [[ $deleteDirectoriesLength -eq 0 ]]; then
        text_yellow "[DeleteDirectory] No directories to delete\n"
        return
    else
        text_green "[DeleteDirectory] Deleting ${deleteDirectoriesLength} directories...\n"
    fi

    for ((i = 0; i < deleteDirectoriesLength; i++)); do
        deleteDirectory=$(jq -r ".deleteDirectories[$i]" "$json_config_path")
        dir_to_delete="$project_dir/$deleteDirectory"

        dir_to_delete=$(expand_placeholders "$dir_to_delete")

        if [[ "$dry_run" == "" ]] && [[ ! -d "$dir_to_delete" ]]; then
            echo "[DeleteDirectory] Directory not found: $dir_to_delete"
            continue
        fi

        $dry_run rm -rf "$dir_to_delete" || text_red "[DeleteDirectory] Failed to delete directory: $dir_to_delete\n"
    done
}

function get_platform() {
    local platform
    platform=$(uname -s)

    case $platform in
    Linux*) echo "linux" ;;
    Darwin*) echo "macos" ;;
    CYGWIN* | MSYS* | MINGW*) echo "windows" ;;
    *) echo "unknown" ;;
    esac
}

function expand_placeholders() { # 1: string
    local value="$1"

    value="${value//\{\{deploy_dir\}\}/$deploy_dir_escaped}"
    value="${value//\{\{label\}\}/$launchagent_label}"
    value="${value//\{\{name:lowercase\}\}/$launchagent_name_lowercase}"
    value="${value//\{\{name\}\}/$launchagent_name}"
    value="${value//\{\{organization\}\}/$org_id}"
    value="${value//\{\{project\}\}/$project_name}"
    value="${value//\{\{project_dir\}\}/$project_dir_escaped}"
    value="${value//\{\{title\}\}/$launchagent_title}"

    echo "$value"
}

json_config=
json_config_path=create-launchagent.json
platform=$(get_platform)

dry_run=false
overwrite_target_dir=false
template_source_dir=.
yes=false

while getopts ":${script_switches}${script_options}" opt; do
    case $opt in
    h) usage ;;
    o) overwrite_target_dir=true ;;
    t) template_source_dir="$OPTARG" ;;
    y) yes=true ;;
    z) dry_run=true ;;
    :) end "Missing argument" >&2 ;;
    \?) end "Invalid option" >&2 ;;
    esac
done
shift $((OPTIND - 1))

[[ $# -eq 6 ]] || usage

org_id=$(echo "$1" | tr '[:upper:]' '[:lower:]')
project_name="$2"
launchagent_name="$3"
launchagent_title="$4"
target_parent_dir="$5"
deploy_dir="$6"

launchagent_name_lowercase=$(echo "$launchagent_name" | tr '[:upper:]' '[:lower:]')
launchagent_label="$org_id.$launchagent_name_lowercase"
project_dir="$target_parent_dir/$project_name"

if [[ -z "$org_id" || -z "$project_name" || -z "$launchagent_name" || -z "$launchagent_title" || -z "$target_parent_dir" || -z "$deploy_dir" ]]; then
    usage
elif [[ ! -d "$template_source_dir" ]]; then
    end "Source directory not found: $template_source_dir" 1
elif [[ ! "$project_name" =~ ^[A-Z][a-zA-Z0-9_.]+[a-zA-Z0-9]$ ]]; then
    end "Invalid project name '$project_name'. Must be a valid C# project name (e.g. MyNamespace.FooBar)." 1
elif [[ ! "$launchagent_name" =~ ^[A-Z][a-zA-Z0-9_]+[a-zA-Z0-9]$ ]]; then
    end "Invalid launch agent name '$launchagent_name'. Must be a valid C# class name (e.g. FooBar)." 1
elif [[ ! "$org_id" =~ ^[a-z0-9]+(\.[a-z0-9-]+)*$ ]]; then
    end "Invalid organization identifier '$org_id'. Must be a valid reverse domain (e.g. com.example, net.example)." 1
fi

deploy_dir_escaped="${deploy_dir//\//\\/}"
project_dir_escaped="${project_dir//\//\\/}"

template_source_dir=$(realpath "$template_source_dir")
json_config_path="$template_source_dir/$json_config_path"

if [[ ! -f "$json_config_path" ]]; then
    end "Configuration file not found: $json_config_path" 1
fi

verify_use
read_json_config

echo "$script_title"
echo "• Organization Identifier: $org_id"
echo "• Launch Agent: $launchagent_name"
echo "• Project Name: $project_name"
echo "• Project Path: $project_dir"
echo "• Source: $template_source_dir"
echo "• Deploy Directory: $deploy_dir"
[[ $overwrite_target_dir == false ]] || echo "• Overwrite project directory (if exists)"
[[ $dry_run == false ]] || echo "• Dry-run (output commands only)"
confirm_run

if [[ $dry_run == true ]]; then
    dry_run="echo"
else
    dry_run=""
fi

if [[ -d "$project_dir" ]]; then
    if [[ $overwrite_target_dir != true ]]; then
        end "Directory already exists (use -o to overwrite): $project_dir" 1
    else
        text_green "[RemoveDirectory] Removing existing directory: $project_dir\n"
        $dry_run rm -rf "$project_dir" || end "Failed to remove existing directory: $project_dir" 1
    fi
fi

text_green "[MakeDirectory] Creating project directory: $project_dir\n"
$dry_run mkdir -p "$project_dir" || end "Failed to create project directory: $project_dir" 1

copy_directories
copy_files
replace_in_files
rename_files
rename_directories
delete_directories

if [[ ! -d "$deploy_dir" ]]; then
    text_green "[MakeDirectory] Creating deploy directory: $deploy_dir\n"
    $dry_run mkdir -p "$deploy_dir" || {
        text_red "Failed to create deploy directory '$deploy_dir'. "
        echo "You'll need to create this directory manually and set appropriate permissions."
    }
fi

[[ "$dry_run" != "" ]] || end "New launch agent project created successfully: $project_dir" 0
