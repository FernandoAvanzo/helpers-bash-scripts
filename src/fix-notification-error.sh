#!/bin/bash

function create_sym_link() {
    local sub_folder_path="$1"
    local clojure_link="$sub_folder_path/clojure"
    echo "Creating symbolic link in: $sub_folder_path"
    ln -sf /usr/local/bin/clojure "$clojure_link"
    echo "The symbolic link created at: $clojure_link"

    # Make the symbolic link executable
    echo "Making symbolic link executable"
    chmod +x "$clojure_link"
    echo "The symbolic link is now executable"
}

function create_sym_link_in_subfolders() {
    local base_path="$1"
    echo "Starting to create symbolic links in sub-folders of: $base_path"
    find "$base_path" -maxdepth 1 -type d -name "*nimbus*" | while IFS= read -r sub_folder_path; do
        echo "Working on the subfolder: $sub_folder_path"
        create_sym_link "$sub_folder_path"
        echo "$sub_folder_path/clojure" >> "$base_path/.git/info/exclude"
        echo "Added $sub_folder_path/clojure to the git exclude file"
    done
    echo "Finished creating symbolic links."
}

# Use it like this:
create_sym_link_in_subfolders "$NU_HOME/nimbus"
