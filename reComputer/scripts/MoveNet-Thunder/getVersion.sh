#!/bin/bash
# based on dusty - https://github.com/dusty-nv/jetson-containers/blob/master/jetson_containers/l4t_version.sh
# and llama-factory init script

# we only have images for these - 36.2.0 works on 36.3.0
L4T_VERSIONS=("35.3.1", "35.4.1", "36.2.0", "36.3.0")

ARCH=$(uname -i)
# echo "ARCH:  $ARCH"

if [ $ARCH = "aarch64" ]; then
	L4T_VERSION_STRING=$(head -n 1 /etc/nv_tegra_release)

	if [ -z "$L4T_VERSION_STRING" ]; then
		#echo "reading L4T version from \"dpkg-query --show nvidia-l4t-core\""

		L4T_VERSION_STRING=$(dpkg-query --showformat='${Version}' --show nvidia-l4t-core)
		L4T_VERSION_ARRAY=(${L4T_VERSION_STRING//./ })

		#echo ${L4T_VERSION_ARRAY[@]}
		#echo ${#L4T_VERSION_ARRAY[@]}

		L4T_RELEASE=${L4T_VERSION_ARRAY[0]}
		L4T_REVISION=${L4T_VERSION_ARRAY[1]}
	else
		#echo "reading L4T version from /etc/nv_tegra_release"

		L4T_RELEASE=$(echo $L4T_VERSION_STRING | cut -f 2 -d ' ' | grep -Po '(?<=R)[^;]+')
		L4T_REVISION=$(echo $L4T_VERSION_STRING | cut -f 2 -d ',' | grep -Po '(?<=REVISION: )[^;]+')
	fi

	L4T_REVISION_MAJOR=${L4T_REVISION:0:1}
	L4T_REVISION_MINOR=${L4T_REVISION:2:1}

	L4T_VERSION="$L4T_RELEASE.$L4T_REVISION"

	IMAGE_TAG=$L4T_VERSION

	#echo "L4T_VERSION :  $L4T_VERSION"
	#echo "L4T_RELEASE :  $L4T_RELEASE"
	#echo "L4T_REVISION:  $L4T_REVISION"

elif [ $ARCH != "x86_64" ]; then
	echo "unsupported architecture:  $ARCH"
	exit 1
fi


if [[ ! " ${L4T_VERSIONS[@]} " =~ " ${L4T_VERSION} " ]]; then
    echo "L4T_VERSION is not in the allowed versions list. Exiting."
    exit 1
fi

# check if 36 to change IMAGE_TAG
if [ ${L4T_RELEASE} -eq "36" ]; then
	# image tag will be 2.0
	IMAGE_TAG="36.2.0"
fi

