#!/bin/bash

function remove_clojure_link() {
    local folder_path="$1"
    local clojure_link="$folder_path/clojure"
    local git_exclude_path="$NU_HOME/nimbus/.git/info/exclude"
    if [[ -e "$clojure_link" ]]; then
        echo "Removing the clojure link from: $folder_path"
        rm "$clojure_link"
	echo "$clojure_link link removed successfully"

	if grep -q "$clojure_link" "$git_exclude_path"; then
	    echo "Removing $clojure_link path from git exclude file"
	    sed -i.bak "/$clojure_link/d" "$git_exclude_path"
	    echo "$clojure_link path removed from git exclude file"
	else
	    echo "$clojure_link path not found in git exclude file"
	fi
    else
        echo "Could not find clojure link in: $folder_path"
    fi
}

function remove_clojure_link_in_subfolders() {
    local base_path="$1"
    echo "Starting to remove clojure links in subfolders of: $base_path"
    find "$base_path" -type d -name "*nimbus*" | while IFS= read -r sub_folder_path; do
        echo "Working on the subfolder: $sub_folder_path"
        remove_clojure_link "$sub_folder_path"
    done
    echo "Finished removing clojure links."
}

# Use it like this:
remove_clojure_link_in_subfolders "$NU_HOME/nimbus"
