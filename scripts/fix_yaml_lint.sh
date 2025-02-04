#!/bin/bash

# Function to fix YAML file
fix_yaml_file() {
    local file="$1"
    
    # Ensure file exists and is not empty
    if [ ! -s "$file" ]; then
        echo "Creating minimal valid YAML content for $file"
        echo "# Configuration for $(basename "$file")" > "$file"
    fi
    
    # Remove trailing spaces
    sed -i '' 's/[[:space:]]*$//' "$file"
    
    # Ensure exactly one newline at end of file
    if [ -n "$(tail -c1 "$file")" ]; then
        echo "" >> "$file"
    fi
    
    echo "Fixed: $file"
}

# Find all YAML files
find . -type f \( -name "*.yml" -o -name "*.yaml" \) -not -path "*/\.*" | while read -r file; do
    fix_yaml_file "$file"
done 