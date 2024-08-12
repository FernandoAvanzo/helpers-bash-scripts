#!/bin/bash

global_source=$1
global_destination=$2

create_tar_gz() {
    # Check if the correct number of arguments is provided
    if [ $# -ne 2 ]; then
        echo "Usage: create_tar_gz <source_folder> <destination_path>"
        return 1
    fi

    local source_folder=$1
    local destination_path=$2

    # Check if the source folder exists
    if [ ! -d "$source_folder" ]; then
        echo "Error: Source folder '$source_folder' does not exist."
        return 1
    fi

    # Create the tar.gz file
    local folder_name
    folder_name=$(basename "$source_folder")
    tar -czf "$destination_path/${folder_name}.tar.gz" -C "$source_folder" .

    # Verify if the tar.gz file was created successfully
    if [ $? -eq 0 ]; then
        echo "Successfully created $destination_path/${folder_name}.tar.gz"
        return 0
    else
        echo "Error: Failed to create tar.gz file."
        return 1
    fi
}

# Example usage:
create_tar_gz "$global_source" "$global_destination"