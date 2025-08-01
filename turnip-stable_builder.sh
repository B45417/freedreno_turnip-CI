#!/bin/bash -e
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'

deps="meson ninja patchelf unzip curl pip flex bison zip git"
workdir="$(pwd)/turnip_workdir"
packagedir="$workdir/turnip_module"
ndkver="android-ndk-r28"
sdkver="30"
mesasrc="https://archive.mesa3d.org/mesa-25.1.7.tar.xz"
mesadir="mesa-25.1.7"
mesaver="25.1.7"

#array of string => commit/branch;patch args
base_patches=(
)
experimental_patches=(
)
failed_patches=()
commit=""
commit_short=""
mesa_version=""
version=""
major=""
minor=""
patch=""
vulkan_version=""
clear

# there are 4 functions here, simply comment to disable.
# you can insert your own function and make a pull request.
run_all(){
	check_deps
	prep

	if (( ${#base_patches[@]} )); then
		prep "patched"
	fi
 
	if (( ${#experimental_patches[@]} )); then
		prep "experimental"
	fi
}

prep () {
	prepare_workdir "$1"
	build_lib_for_android
	port_lib_for_adrenotool "$1"
}

check_deps(){
	pip install meson PyYAML

	echo "Checking system for required Dependencies ..."
	for deps_chk in $deps;
		do
			sleep 0.25
			if command -v "$deps_chk" >/dev/null 2>&1 ; then
				echo -e "$green - $deps_chk found $nocolor"
			else
				echo -e "$red - $deps_chk not found, can't countinue. $nocolor"
				deps_missing=1
			fi;
		done

		if [ "$deps_missing" == "1" ]
			then echo "Please install missing dependencies" && exit 1
		fi

	echo "Installing python Mako dependency (if missing) ..." $'\n'
	pip install mako &> /dev/null
}

prepare_workdir(){
	echo "Creating and entering to work directory ..." $'\n'
	mkdir -p "$workdir" && cd "$_"

	if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
		if [ ! -n "$(ls -d android-ndk*)" ]; then
			echo "Downloading android-ndk from google server (~640 MB) ..." $'\n'
			curl https://dl.google.com/android/repository/"$ndkver"-linux.zip --output "$ndkver"-linux.zip &> /dev/null
			###
			echo "Exracting android-ndk to a folder ..." $'\n'
			unzip "$ndkver"-linux.zip  &> /dev/null
		fi
	else	
		echo "Using android ndk from github image"
	fi

	if [ -z "$1" ]; then
		if [ -d $mesadir ]; then
			echo "Removing old mesa ..." $'\n'
		 	rm -rf $mesadir
		fi
	
		echo "Downloading mesa source ..." $'\n'
		curl "$mesasrc" --output mesa.tar.xz &> /dev/null
		
		echo "Exracting mesa source ..." $'\n'
		tar -xf mesa.tar.xz

		cd $mesadir
		# commit_short=$(git rev-parse --short HEAD)
		# commit=$(git rev-parse HEAD)
		mesa_version=$(cat VERSION | xargs)
		version=$(awk -F'COMPLETE VK_MAKE_API_VERSION(|\n#define)' '{print $2}' <<< $(cat include/vulkan/vulkan_core.h) | xargs)
		major=$(echo $version | cut -d "," -f 2 | xargs)
		minor=$(echo $version | cut -d "," -f 3 | xargs)
		patch=$(awk -F'VK_HEADER_VERSION |\n#define' '{print $2}' <<< $(cat include/vulkan/vulkan_core.h) | xargs)
		vulkan_version="$major.$minor.$patch"										
	else		
		cd $mesadir

		if [ $1 == "patched" ]; then 
			apply_patches ${base_patches[@]}
		else 
			apply_patches ${experimental_patches[@]}
		fi
		
	fi
}

apply_patches() {
	local arr=("$@")
	for patch in "${arr[@]}"; do
		echo "Applying patch $patch"
		patch_source="$(echo $patch | cut -d ";" -f 2 | xargs)"
		patch_args=$(echo $patch | cut -d ";" -f 3 | xargs)
		if [[ $patch_source == *"../.."* ]]; then
			if git apply $patch_args "$patch_source"; then
                            echo "Patch applied successfully"
			else
                            echo "Failed to apply $patch"
			    failed_patches+=("$patch")
			fi
		else 
			patch_file="${patch_source#*\/}"
			curl --output "../$patch_file".patch -k --retry-delay 30 --retry 5 -f --retry-all-errors https://gitlab.freedesktop.org/mesa/mesa/-/"$patch_source".patch
			sleep 1

			if git apply $patch_args "../$patch_file".patch; then
				echo "Patch applied successfully"
			else
				echo "Failed to apply $patch"
				failed_patches+=("$patch")
				
			fi
		fi
	done
}

patch_to_description() {
	local arr=("$@")
	for patch in "${arr[@]}"; do
		patch_name="$(echo $patch | cut -d ";" -f 1 | xargs)"
		patch_source="$(echo $patch | cut -d ";" -f 2 | xargs)"
		patch_args="$(echo $patch | cut -d ";" -f 3 | xargs)"
		if [[ $patch_source == *"../.."* ]]; then
			echo "- $patch_name, $patch_source, $patch_args" >> description
		else 
			echo "- $patch_name, [$patch_source](https://gitlab.freedesktop.org/mesa/mesa/-/$patch_source), $patch_args" >> description
		fi
	done
}

build_lib_for_android(){
	echo "Creating meson cross file ..." $'\n'
	if [ -z "${ANDROID_NDK_LATEST_HOME}" ]; then
		ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
	else	
		ndk="$ANDROID_NDK_LATEST_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
	fi

	cat <<EOF >"android-aarch64"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

	echo "Generating build files ..." $'\n'
	meson setup build-android-aarch64 \
		--cross-file "$workdir"/"$mesadir"/android-aarch64 \
		-Dbuildtype=release \
		-Dplatforms=android \
		-Dplatform-sdk-version=$sdkver \
		-Dandroid-stub=true \
		-Dvulkan-drivers=freedreno \
                -Dvulkan-beta=true \
		-Degl=disabled \
                -Dgallium-drivers= \
		-Dfreedreno-kmds=kgsl \
                -Db_lto=true \
		-Dstrip=true &> "$workdir"/meson_log

	echo "Compiling build files ..." $'\n'
	ninja -C build-android-aarch64 &> "$workdir"/ninja_log
}

port_lib_for_adrenotool(){
	echo "Using patchelf to match soname ..."  $'\n'
	cp "$workdir"/"$mesadir"/build-android-aarch64/src/freedreno/vulkan/libvulkan_freedreno.so "$workdir"
	cd "$workdir"
	patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so
	mv libvulkan_freedreno.so vulkan.adreno.so

	if ! [ -a vulkan.adreno.so ]; then
		echo -e "$red Build failed! $nocolor" && exit 1
	fi

	mkdir -p "$packagedir" && cd "$_"

	date=$(date +'%b %d, %Y')
	suffix=""

	if [ ! -z "$1" ]; then
		suffix="_$1"
	fi

	cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip - $mesaver$suffix",
  "description": "Compiled from Mesa $mesaver stable",
  "author": "mesa",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "vk$vulkan_version",
  "minApi": 30,
  "libraryName": "vulkan.adreno.so"
}
EOF

	filename=Turnip_$mesaver
	echo "Copy necessary files from work directory ..." $'\n'
	cp "$workdir"/vulkan.adreno.so "$packagedir"

	echo "Packing files in to adrenotool package ..." $'\n'
	zip -9 "$workdir"/"$filename$suffix".zip ./*

	cd "$workdir"

	if [ -z "$1" ]; then
		echo "Turnip - $mesa_version - $date" > release
		echo "$mesa_version"_"$commit_short" > tag
		echo  $filename > filename
		echo "### Stable release" > description
		echo "false" > patched
		echo "false" > experimental
	else		
		if [ $1 == "patched" ]; then 
			echo "## Upstreams / Patches" >> description
			echo "These have not been merged by Mesa officially yet and may introduce bugs or" >> description
			echo "we revert stuff that breaks games but still got merged in (see --reverse)" >> description
			patch_to_description ${base_patches[@]}
			echo "true" > patched
			echo "" >> description
			echo "_Upstreams / Patches are only applied to the patched version (\_patched.zip)_" >> description
			echo "_If a patch is not present anymore, it's most likely because it got merged, is not needed anymore or was breaking something._" >> description
		else 
			echo "### Upstreams / Patches (Experimental)" >> description
			echo "Include previously listed patches + experimental ones" >> description
			patch_to_description ${experimental_patches[@]}
			echo "true" > experimental
			echo "" >> description
			echo "_Experimental patches are only applied to the experimental version (\_experimental.zip)_" >> description
		fi
	fi

	if (( ${#failed_patches[@]} )); then
		echo "" >> description
		echo "#### Patches that failed to apply" >> description
		patch_to_description ${failed_patches[@]}
	fi
	
	if ! [ -a "$workdir"/"$filename".zip ];
		then echo -e "$red-Packing failed!$nocolor" && exit 1
		else echo -e "$green-All done, you can take your zip from this folder;$nocolor" && echo "$workdir"/
	fi
}

run_all
