#!/bin/bash
# tools/pull_arch_apks.sh
# Downloads F-Droid and MicroG apps for a target ABI or for universal (fat / Java-only) builds.
# Usage: pull_arch_apks.sh <arch> <temp_dir>
#   arch: universal | x86_64 | x86 | arm64-v8a | armeabi-v7a

set -e

TARGET_ARCH=$1
TEMP_DIR=$2
if [ -z "$TARGET_ARCH" ] || [ -z "$TEMP_DIR" ]; then
    echo "Usage: $0 <universal|x86_64|x86|arm64-v8a|armeabi-v7a> <temp_dir>"
    exit 1
fi

SUB_ARCH=""
case $TARGET_ARCH in
    "x86_64") SUB_ARCH="x86" ;;
    "arm64-v8a") SUB_ARCH="armeabi-v7a" ;;
    "x86") SUB_ARCH="x86" ;;
    "armeabi-v7a") SUB_ARCH="armeabi-v7a" ;;
    "universal"|"") SUB_ARCH="" ;;
    *) echo "Unknown arch $TARGET_ARCH" >&2; exit 1 ;;
esac

# F-Droid Mirrors and Apps
FDROID_MIRRORS=(
    "https://f-droid.org/repo/"
    "https://bubu1.eu/fdroid/repo/"
    "https://ftp.fau.de/fdroid/repo/"
    "https://apt.izzysoft.de/fdroid/repo/"
)
MICROG_REPO="https://microg.org/fdroid/repo"

# package:apk_filename:install_name:dest_dir[:extract_libs]
FDROID_APPS=(
    "org.fdroid.fdroid.privileged:FDroidPrivilegedExtension:FDroidPrivilegedExtension:priv-app"
    "com.aurora.services:AuroraServices:AuroraServices:priv-app"
    "org.fitchfamily.android.dejavu:DejaVuBackend:DejaVuBackend:app"
    "org.microg.nlp.backend.nominatim:NominatimGeocoderBackend:NominatimGeocoderBackend:app"
)

MICROG_APPS=(
    "com.google.android.gms:GmsCore:GmsCore:priv-app:libs"
    "com.google.android.gsf:GsfProxyA5K:GoogleServicesFramework:priv-app:"
    "com.android.vending:FakeStore:Phonesky:priv-app:"
)

mkdir -p "$TEMP_DIR/cache/fdroid"
cd "$TEMP_DIR/cache/fdroid"

get_fdroid_index() {
    if [ ! -f fdroid_index.xml ]; then
        for url in "${FDROID_MIRRORS[@]}"; do
            echo "Trying mirror: $url"
            if wget -q --connect-timeout=10 --tries=2 "${url}index.jar" -O index.jar; then
                unzip -p index.jar index.xml > fdroid_index.xml
                FDROID_ACTIVE_REPO="$url"
                return 0
            fi
        done
        echo "Failed to download F-Droid index."
        exit 1
    else
        FDROID_ACTIVE_REPO="${FDROID_MIRRORS[0]}"
    fi
}

get_microg_index() {
    if [ ! -f microg_index.xml ]; then
        wget -q --connect-timeout=10 --tries=2 "${MICROG_REPO}/index.jar" -O microg_index.jar
        unzip -p microg_index.jar index.xml > microg_index.xml
    fi
}

get_fdroid_index
get_microg_index

download_app() {
    local package=$1
    local module_name=$2
    local install_name=$3
    local dest_dir=$4
    local extract_libs=$5
    local repo_url=$6
    local index_file=$7

    echo "Processing $package for $TARGET_ARCH..."
    
    local apk=""
    local native=""
    local hash=""
    local min_api=""
    local index=1
    
    while true; do
        apk="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package['$index']' -v ./apkname "$index_file" 2> /dev/null || true)"
        native="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package['$index']' -v ./nativecode "$index_file" 2> /dev/null || true)"
        
        if [ -z "$apk" ]; then break; fi
        if [ "$TARGET_ARCH" = "universal" ]; then
            # Prefer Java-only APKs, then multi-ABI fat APKs (comma-separated nativecode)
            if [ -z "$native" ] || echo "$native" | grep -q ','; then
                break
            fi
        elif [ -n "$TARGET_ARCH" ]; then
            if [ -z "$native" ] || echo "$native" | grep -q "$TARGET_ARCH" || echo "$native" | grep -q "$SUB_ARCH"; then
                break
            fi
        else
            break
        fi

        index=$((index + 1))
    done

    if [ -z "$apk" ]; then
        # Fallback to first if no arch matched perfectly (or maybe fail?)
        apk="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package[1]' -v ./apkname "$index_file" 2> /dev/null || true)"
        native="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package[1]' -v ./nativecode "$index_file" 2> /dev/null || true)"
        index=1
    fi

    if [ -n "$apk" ]; then
        hash="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package['$index']/hash[@type="sha256"]' -v . "$index_file" 2> /dev/null || true)"
        min_api="$(xmlstarlet sel -t -m '//application[id="'"$package"'"]/package['$index']' -v ./sdkver "$index_file" 2> /dev/null || true)"
        
        if [ "$TARGET_ARCH" = "universal" ] && [ -n "$native" ]; then
            echo "Found universal APK: $apk (ABIs: $native, hash: $hash)"
        elif [ "$TARGET_ARCH" = "universal" ]; then
            echo "Found universal APK: $apk (Java-only, hash: $hash)"
        else
            echo "Found APK: $apk (hash: $hash)"
        fi
        
        # Download APK (replace any bundled copy from another architecture)
        local out_apk="$TEMP_DIR/zip-content/origin/$dest_dir/$module_name.apk"
        mkdir -p "$(dirname "$out_apk")"
        rm -f "$out_apk"

        local retries=0
        while ! wget -q --connect-timeout=10 "${repo_url%/}/$apk" -O "$out_apk"; do
            retries=$((retries+1))
            if [ "$retries" -ge 3 ]; then
                echo "Failed to download $apk"
                exit 1
            fi
            sleep 1
        done

        # Verify hash
        local actual_hash
        actual_hash=$(sha256sum "$out_apk" | awk '{print $1}')
        if [ "$actual_hash" != "$hash" ]; then
            echo "Hash mismatch for $module_name! Expected $hash, got $actual_hash"
            exit 1
        fi
        
        # Write to file-list.dat
        # LOCAL_PATH/LOCAL_FILENAME|MIN_API|MAX_API|FINAL_FILENAME|_extract_libs|INTERNAL_NAME|FILE_HASH
        # We replace any existing entry for this module in file-list.dat to avoid duplicates
        grep -v -e "${dest_dir}/${module_name}|" -e "/${module_name}|" -- "$TEMP_DIR/zip-content/origin/file-list.dat" > "$TEMP_DIR/zip-content/origin/file-list.dat.tmp" || true
        mv "$TEMP_DIR/zip-content/origin/file-list.dat.tmp" "$TEMP_DIR/zip-content/origin/file-list.dat"
        
        echo "$dest_dir/$module_name|${min_api}||${install_name}|$extract_libs|$package|$hash" >> "$TEMP_DIR/zip-content/origin/file-list.dat"
        
    else
        echo "WARNING: Could not find $package in $index_file; dropping bundled ${module_name}.apk if present"
        rm -f "$TEMP_DIR/zip-content/origin/$dest_dir/$module_name.apk"
    fi
}

for app in "${FDROID_APPS[@]}"; do
    IFS=':' read -r pkg module install_name dir <<< "$app"
    download_app "$pkg" "$module" "$install_name" "$dir" "" "$FDROID_ACTIVE_REPO" "fdroid_index.xml"
done

for app in "${MICROG_APPS[@]}"; do
    IFS=':' read -r pkg module install_name dir extract <<< "$app"
    download_app "$pkg" "$module" "$install_name" "$dir" "$extract" "$MICROG_REPO" "microg_index.xml"
done
