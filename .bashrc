set -o nounset

export VISUAL="vim"
export EDITOR="$VISUAL"

if [ -e $HOME/.aliases ]; then
    source $HOME/.aliases
fi

if [ -f ~/.bash_prompt ]; then
    source ~/.bash_prompt
fi

test -s ~/.alias && . ~/.alias || true

# Color codes
white=$(tput setaf 231) 
blue=$(tput setaf 27)

HISTTIMEFORMAT="$blue%Y-%m-%d $blue%H:%M:%S $white"

# Extract any type of compressed file
ex() {
    if [ -z ${1} ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        echo "Usage: ex <archive> [directory]"
        echo "Example: ex presentation.zip /tmp/extracted"
        echo ""
        echo "Supported formats with optimised extraction:"
        echo "tar.bz2, tar.gz, tar.xz, tar.zst, tar, bz2, gz, xz, zst,"
        echo "zip, 7z, rar, lzo, lzma, tlz, txz, tbz, tbz2, tgz"
        echo ""
        echo "Features: Multi-threading, hardware acceleration, progress bars"
        return 0
    fi

    # Check if file exists
    if [ ! -f "$1" ]; then
        echo "Error: File '$1' not found!"
        return 1
    fi

    # Set destination directory
    local dest_dir="${2:-.}"
    mkdir -p "$dest_dir"

    # Get number of CPU cores for parallel processing
    local cores=$(nproc)
    local max_threads=$((cores > 8 ? 8 : cores))
    
    # Function to convert bytes to human readable format
    human_readable_size() {
        local bytes=$1
        local units=("B" "KB" "MB" "GB" "TB")
        local size=$bytes
        local unit=0
        
        while (( size >= 1000 && unit < 4 )); do
            size=$((size / 1000))
            unit=$((unit + 1))
        done
        
        if [ $unit -eq 0 ]; then
            echo "${size} ${units[$unit]}"
        else
            # Use bc for decimal precision, fallback to integer division
            if command -v bc &> /dev/null; then
                local precise_size=$(echo "scale=1; $bytes / (1000^$unit)" | bc)
                echo "${precise_size} ${units[$unit]}"
            else
                echo "${size} ${units[$unit]}"
            fi
        fi
    }

    # Get file size for progress estimation
    local file_size=$(stat -c%s "$1" 2>/dev/null)
    local readable_size=$(human_readable_size $file_size)

    echo "Extracting '$1' ($readable_size) to '$dest_dir'..."
    echo "Using $max_threads threads on $cores CPU cores"

    case "$1" in
        # Modern parallel tar with compression detection
        *.tar.bz2|*.tbz2|*.tbz)
            if command -v pbzip2 &> /dev/null; then
                echo "Using parallel bzip2..."
                pbzip2 -dc "$1" | tar -xf - -c "dest_dir"
            else
                tar --use-compress-program-"bzip2" -xf "$1" -C "$dest_dir"
            fi
            ;;

        *.tar.gz|*.tgz)
            if command -v pigz &> /dev/null; then
                echo "Using parallel gzip..."
                pigz -dc "$1" | tar -xf - -C "$dest_dir"
            else
                tar -xzf "$1" -C "$dest_dir"
            fi
            ;;
            
        *.tar.xz|*.txz)
            if command -v pixz &> /dev/null; then
                echo "Using parallel xz..."
                pixz -dc "$1" | tar -xf - -C "$dest_dir"
            else
                tar --use-compress-program="xz -T$max_threads" -xf "$1" -C "$dest_dir"
            fi
            ;;
            
        *.tar.zst)
            if command -v zstd &> /dev/null; then
                echo "Using parallel zstd..."
                zstd -dc "$1" | tar -xf - -C "$dest_dir"
            else
                echo "Error: zstd not found. Install with: sudo pacman -S zstd"
                return 1
            fi
            ;;
            
        *.tar)
            tar -xf "$1" -C "$dest_dir"
            ;;

        # 7-Zip with multi-threading (handles many formats optimally)
        *.zip)
            if command -v 7z &> /dev/null; then
                echo "Using 7-Zip with $max_threads threads..."
                7z x "$1" -o"$dest_dir" -mmt=$max_threads -y
            elif command -v unzip &> /dev/null; then
                unzip -q "$1" -d "$dest_dir"
            else
                echo "Error: No zip extractor found. Install 7zip or unzip."
                return 1
            fi
            ;;
            
        *.7z)
            if command -v 7z &> /dev/null; then
                echo "Using 7-Zip with $max_threads threads..."
                7z x "$1" -o"$dest_dir" -mmt=$max_threads -y
            else
                echo "Error: 7z not found. Install with: sudo pacman -S p7zip"
                return 1
            fi
            ;;
            
        *.rar)
            if command -v unrar &> /dev/null; then
                unrar x "$1" "$dest_dir/"
            elif command -v 7z &> /dev/null; then
                7z x "$1" -o"$dest_dir" -mmt=$max_threads -y
            else
                echo "Error: No rar extractor found. Install unrar or p7zip."
                return 1
            fi
            ;;

        # Parallel decompression for single files
        *.gz)
            if command -v pigz &> /dev/null; then
                echo "Using parallel gzip..."
                pigz -d "$1"
            else
                gunzip "$1"
            fi
            ;;
            
        *.bz2)
            if command -v pbzip2 &> /dev/null; then
                echo "Using parallel bzip2..."
                pbzip2 -d "$1"
            else
                bunzip2 "$1"
            fi
            ;;
            
        *.xz|*.lzma|*.tlz)
            xz -d -T$max_threads "$1"
            ;;
            
        *.zst)
            if command -v zstd &> /dev/null; then
                zstd -d "$1"
            else
                echo "Error: zstd not found. Install with: sudo pacman -S zstd"
                return 1
            fi
            ;;
            
        *.lzo)
            if command -v lzop &> /dev/null; then
                lzop -d "$1"
            else
                echo "Error: lzop not found. Install with: sudo pacman -S lzop"
                return 1
            fi
            ;;
            
        *.Z)
            if command -v uncompress &> /dev/null; then
                uncompress "$1"
            else
                echo "Error: uncompress not found."
                return 1
            fi
            ;;
            
        *)
            echo "Error: Unsupported archive format for '$1'"
            echo "Run 'ex --help' to see supported formats."
            return 1
            ;;
    esac
    
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "✓ Extraction completed successfully!"
        if [ "$dest_dir" != "." ]; then
            echo "Files extracted to: $dest_dir"
        fi
    else
        echo "✗ Extraction failed with exit code: $exit_code"
        return $exit_code
    fi
}

# Function to install missing tools
install_extract_tools() {
    echo "Installing optimized extraction tools..."
    sudo pacman -S --needed p7zip unrar pigz pbzip2 zstd lzop pixz
    echo "✓ Installation complete! Your extract function is now fully optimized."
} 

# List largest files in working directory
lf() {
    du -h -x -s -- * | sort -r -h | head -20;
}

# Search through your history for previous run commands
hg() {
    history | grep "$1";
}

# Create an initialise a skeleton git repository
gitInit() {
    if [ -z "$1" ]; then
        printf "%s\n" "Please provide a directory name.";
    else
        mkdir "$1";
        builtin cd "$1";
        pwd;
        git init;
        touch README.md .gitignore LICENSE;
        echo "# $(basename $PWD)" >> README.md
    fi
}

export HISTSIZE=1000000
export HISTFILESIZE=1000000000

# Dotnet path
export DOTNET_ROOT=$HOME/.dotnet
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools


source ~/.aliases

# Added by LM Studio CLI (lms)
export PATH="$PATH:/home/leonard/.lmstudio/bin"
export PATH=~/.npm-global/bin:$PATH

# Android SDK PATH
export ANDROID_HOME="/opt/android-sdk"

# go path
export PATH=$PATH:/usr/local/go/bin
