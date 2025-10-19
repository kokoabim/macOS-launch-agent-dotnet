#!/usr/bin/env bash

set -eo pipefail

script_name="${0##*/}"
script_title="Manage Launch Agent"
script_version="1.0"
script_action=status

dotnet_runtime="osx-arm64"
launchagent_name=AGENTNAME_CHANGEME
launchagent_label=me.swsj.launch-agent
project_name=Kokoabim.LaunchAgent
launchagents_base_dir=/opt/kokoabim
build_dir=./build

script_options="d:l:n:p:r:"
script_switches="hiosy"

function usage() {
    end "$(text_bold "$script_title") (v$script_version)
Usage: $(text_bold "$(text_green "$script_name")") [-$script_switches] [-${script_options//:/} <$(text_underline value)>] <$(text_underline action)> [<$(text_underline user)>]

$(text_underline Action:)
 build    Build launch agent files
 copy     Copy built launch agent files and create symlink
 delete   Delete launch agent files and symlink
 deploy   Build, copy and enable launch agent
 disable  Disable launch agent
 enable   Enable launch agent
 status   View launch agent stats (default if no action provided)

$(text_underline Options:)
 -d <dir>      Launch agents base directory (for copy and deploy actions; default: $(text_italic "$launchagents_base_dir"))
 -l <label>    Launch agent label (default: $(text_italic "$launchagent_label"))
 -n <name>     Launch agent name (default: $(text_italic "$launchagent_name"))
 -p <project>  Project name (for build action; default: $(text_italic "$project_name"))
 -r <runtime>  .NET runtime (for build action; default: $(text_italic "$dotnet_runtime"))

$(text_underline Switches:)
 -h  Show this help
 -i  Include .NET runtime (for build action; default: not included)
 -o  Overwrite build and/or launch agent directory (for build, copy and deploy actions; default: do not overwrite)
 -s  Do not package as single-file (for build, copy and deploy actions; default: single-file)
 -y  Confirm yes to run
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

function confirm_run() {
    if [[ ${yes:-false} == true ]]; then
        return
    fi

    read -r -p "Continue? [y/N] " -n 1
    [[ $REPLY == "" ]] && echo -en "\033[1A" >&2
    echo >&2
    [[ $REPLY =~ ^[Yy]$ ]]
}

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

function build_project() {
    set -eo pipefail

    if [[ -d "$build_dir" ]]; then
        if [[ "$overwrite_targets" == true ]]; then
            rm -rf "$build_dir"
        else
            end "Build directory '$build_dir' already exists. Use -o to overwrite." 1
        fi
    fi

    text_bold "Building project...\n"
    dotnet publish "src/$project_name/$project_name.csproj" -c Release -r "$dotnet_runtime" -p:PublishSingleFile=$package_single_file --self-contained $include_dotnet_runtime -o "$build_dir"
    chown -R "$user_name:$group_name" "$build_dir"
}

function copy_files() {
    set -eo pipefail

    local target_dir=
    local executable_path="$launchagents_base_dir/bin/$launchagent_name"

    if [[ ! -d "$build_dir" ]]; then
        end "Build directory '$build_dir' does not exist. Run build action first." 1
    fi

    if [[ ! -d "$launchagents_base_dir/bin" ]]; then
        mkdir -p "$launchagents_base_dir/bin"
        chown -R "$user_name:$group_name" "$launchagents_base_dir/bin"
    fi

    if [[ -e "$executable_path" ]]; then
        if [[ "$overwrite_targets" == true ]]; then
            rm "$executable_path"
        else
            end "Launch agent executable or symlink '$executable_path' already exists. Use -o to overwrite." 1
        fi
    fi

    if [[ "$package_single_file" == true ]]; then
        echo "Copying single-file executable to '$executable_path'..."
        cp "$build_dir/$launchagent_name" "$executable_path"
    else
        if [[ ! -d "$launchagents_base_dir/consoleapps" ]]; then
            mkdir -p "$launchagents_base_dir/consoleapps"
            chown -R "$user_name:$group_name" "$launchagents_base_dir/consoleapps"
        fi

        target_dir="$launchagents_base_dir/consoleapps/$launchagent_name"

        if [[ -d "$target_dir" ]]; then
            if [[ "$overwrite_targets" == true ]]; then
                rm -rf "$target_dir"
            else
                end "Launch agent directory '$target_dir' already exists. Use -o to overwrite." 1
            fi
        fi

        echo "Copying files to '$target_dir'..."
        mkdir -p "$target_dir"
        cp ./build/* "$target_dir/"
        chown -R "$user_name:$group_name" "$target_dir"

        echo "Creating symlink '$executable_path' → '$target_dir/$launchagent_name'..."
        ln -s "$target_dir/$launchagent_name" "$executable_path"
    fi

    chown "$user_name:$group_name" "$executable_path"
}

function delete_files() {
    set -eo pipefail

    local target_dir=
    local executable_path="$launchagents_base_dir/bin/$launchagent_name"

    if [[ -e "$executable_path" ]]; then
        echo "Removing existing executable or symlink '$executable_path'..."
        rm "$executable_path"
    fi

    if [[ "$package_single_file" == false ]]; then
        target_dir="$launchagents_base_dir/consoleapps/$launchagent_name"

        if [[ -d "$target_dir" ]]; then
            echo "Removing existing directory '$target_dir'..."
            rm -rf "$target_dir"
        fi
    fi
}

function disable_launchagent() {
    set -eo pipefail

    local launchagents_dir="/Users/$user_name/Library/LaunchAgents"
    local launchagent_plist_path="$launchagents_dir/$launchagent_label.plist"

    echo "Disabling launch agent..."
    launchctl bootout "gui/$user_id/$launchagent_name"
    rm "$launchagent_plist_path"
}

function enable_launchagent() {
    set -eo pipefail

    local launchagents_dir="/Users/$user_name/Library/LaunchAgents"
    local launchagent_plist_path="$launchagents_dir/$launchagent_label.plist"

    echo "Enabling launch agent..."
    cp "$launchagent_label.plist" "$launchagents_dir/"
    chown "$user_name:$group_name" "$launchagent_plist_path"
    launchctl bootstrap "gui/$user_id" "$launchagent_plist_path"
}

function view_status() {
    set -eo pipefail

    local launchagents_dir="/Users/$user_name/Library/LaunchAgents"
    local launchagent_plist_path="$launchagents_dir/$launchagent_label.plist"
    local executable_path="$launchagents_base_dir/bin/$launchagent_name"
    local target_dir="$launchagents_base_dir/consoleapps/$launchagent_name"

    text_bold "Files, Directories and Symlinks:\n"
    if [[ -e "$executable_path" ]]; then
        echo "Launch Agent Executable or Symlink: $(text_green "Exists") $(text_light \($executable_path\))"
    else
        echo "Launch Agent Executable or Symlink: $(text_red "Missing") $(text_light \($executable_path\))"
    fi

    if [[ "$package_single_file" == false ]]; then
        if [[ -d "$target_dir" ]]; then
            echo "Launch Agent Directory: $(text_green "Exists") $(text_light \($target_dir\))"
        else
            echo "Launch Agent Directory: $(text_red "Missing") $(text_light \($target_dir\))"
        fi
    fi

    if [[ -e "$launchagent_plist_path" ]]; then
        echo "Launch Agent PList: $(text_green "Exists") $(text_light \($launchagent_plist_path\))"
    else
        echo "Launch Agent PList: $(text_red "Missing") $(text_light \($launchagent_plist_path\))"
    fi

    text_bold "Launch Agent Status:\n"
    launchctl print "gui/$user_id/$launchagent_name" || text_red "Failed to get information about launch agent\n"
}

include_dotnet_runtime=false
overwrite_targets=false
package_single_file=true
yes=false
while getopts ":${script_switches}${script_options}" opt; do
    case $opt in
    d) launchagents_base_dir="$OPTARG" ;;
    h) usage ;;
    i) include_dotnet_runtime=true ;;
    l) launchagent_label="$OPTARG" ;;
    n) launchagent_name="$OPTARG" ;;
    o) overwrite_targets=true ;;
    p) project_name="$OPTARG" ;;
    r) dotnet_runtime="$OPTARG" ;;
    s) package_single_file=false ;;
    y) yes=true ;;
    :) end "Missing argument" >&2 ;;
    \?) end "Invalid option" >&2 ;;
    esac
done
shift $((OPTIND - 1))
script_action="${1:-$script_action}"
shift 1 || :

[[ "$script_action" == "build" || "$script_action" == "copy" || "$script_action" == "delete" || "$script_action" == "deploy" || "$script_action" == "disable" || "$script_action" == "enable" || "$script_action" == "status" ]] || usage

if [[ "$script_action" == "copy" || "$script_action" == "delete" || "$script_action" == "disable" || "$script_action" == "enable" || "$script_action" == "deploy" ]]; then
    [[ $EUID == 0 ]] || end "Run with sudo" 1
fi

if [[ $EUID == 0 ]]; then
    user_name="$1"
    [[ "$user_name" != "" ]] || end "User required for $script_action action" 1
    shift 1 || :

    user_id=$(id -u "$user_name") || end "User '$user_name' does not exist" 1
    group_name=$(id -gn "$user_name") || end "User '$user_name' does not exist" 1
else
    user_id=$(id -u)
    user_name=$(id -un)
    group_name=$(id -gn)
fi

echo "$script_title"
echo "• Action: $script_action"
echo "• Launch Agent Name: $launchagent_name"
if [[ "$script_action" == "build" || "$script_action" == "deploy" ]]; then
    echo "• Project Name: $project_name"
    echo "• .NET Runtime: $dotnet_runtime"
    echo "• Include .NET Runtime: $include_dotnet_runtime"
    echo "• Package as Single-File: $package_single_file"
fi
if [[ "$script_action" == "build" || "$script_action" == "copy" || "$script_action" == "deploy" ]]; then
    echo "• Overwrite Existing Files and Directories: $overwrite_targets"
fi
if [[ "$script_action" == "copy" || "$script_action" == "deploy" || "$script_action" == "delete" || "$script_action" == "status" ]]; then
    echo "• Launch Agents Base Directory: $launchagents_base_dir"
fi
if [[ "$script_action" == "deploy" || "$script_action" == "status" || "$script_action" == "disable" || "$script_action" == "enable"  ]]; then
    echo "• Launch Agent Label: $launchagent_label"
fi

if ! confirm_run; then
    echo "Aborted"
    exit 1
fi

if [[ "$script_action" == "build" || "$script_action" == "deploy" ]]; then
    build_project
fi

if [[ "$script_action" == "disable" || "$script_action" == "deploy" ]]; then
    disable_launchagent
fi

if [[ "$script_action" == "delete" || "$script_action" == "deploy" ]]; then
    delete_files
fi

if [[ "$script_action" == "copy" || "$script_action" == "deploy" ]]; then
    copy_files
fi

if [[ "$script_action" == "enable" || "$script_action" == "deploy" ]]; then
    enable_launchagent
fi

if [[ "$script_action" == "status" ]]; then
    view_status
fi
