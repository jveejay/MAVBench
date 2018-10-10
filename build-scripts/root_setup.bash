#! /bin/bash

env_dir="$(dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd))"
source ${env_dir}/build-scripts/setup_env_var.sh

set -x 
set -e 

# should remove so if the previous runs have failed, it woulnd't cause an 
# issue
rm -f /etc/apt/sources.list.d/ros-latest.list # if we don't remove, we can't be 
                                              # sure which stage last tim

#--- update/upgrade and install relevant packages
echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list
apt-key adv --keyserver hkp://ha.pool.sks-keyservers.net:80 --recv-key 421C365BD9FF1F717815A3895523BAEEB01FA116
echo "deb-src http://packages.ros.org/ros/ubuntu xenial main" >> /etc/apt/sources.list.d/ros-latest.list

apt-get update
##--- install ros-kinetic-desktop-full
apt-get install -y ros-kinetic-desktop-full ros-kinetic-rviz-visual-tools ros-kinetic-ompl

mkdir -p $base_dir/build

# intall ROS OpenCV
if [[ ! -d "$base_dir/build/opencv" ]];then
	cd $base_dir && \
		git clone -b 3.1.0-with-cuda8 https://github.com/daveselinger/opencv opencv
fi

# the following needs to change so that it's not specific to a version of opencv
# (if we want to stick to a version we need to provide the source code ourselves
cd $base_dir/src
if [[ ! -e "ros-kinetic-opencv3_3.3.1-5xenial_arm64.deb" ]];then
    cd $base_dir/src
    rm -rf ros-kinetic-opencv3-3.3.1  
    apt-get source ros-kinetic-opencv3
	cp $base_dir/src/opencv/modules/cudalegacy/src/graphcuts.cpp $base_dir/src/ros-kinetic-opencv3-3.3.1/modules/cudalegacy/src/graphcuts.cpp
    # Dependencies
    cd $base_dir/src/ros-kinetic-opencv3-3.3.1 && \
	   apt-get build-dep -y ros-kinetic-opencv3
    # Now build (we ignore missing dependencies, because we have them on our system anyways)
    sed -i 's/\(\bdh_shlibdeps.*\)$/\1 --dpkg-shlibdeps-params=--ignore-missing-info/' debian/rules || exit 1
	dpkg-buildpackage -b -uc 
fi

 
if [[ ! -e $base_dir/build-deps/ros_install_done.txt ]]; then
    rm -rf /usr/src/deb_mavbench 
    mkdir /usr/src/deb_mavbench
	cp $base_dir/src/ros-kinetic-opencv3_3.3.1-5xenial_arm64.deb /usr/src/deb_mavbench/
    cd /usr/src/deb_mavbench/
    chmod a+wr /usr/src/deb_mavbench && \
	apt-ftparchive packages . | gzip -c9 > Packages.gz && \
	apt-ftparchive sources . | gzip -c9 > Sources.gz && \
	chmod a+wr /etc/apt/sources.list.d/ros-latest.list && \
	echo "deb file:/usr/src/deb_mavbench ./" >> /etc/apt/sources.list.d/ros-latest.list && \
	sed -i -e "1,2s/^/#/g" /etc/apt/sources.list.d/ros-latest.list && \
	apt-get update && \
	apt-get remove -y ros-kinetic-opencv3 && \
	apt-get install -y ros-kinetic-opencv3 --allow-unauthenticated && \
	sed -i -e "s/#//g" /etc/apt/sources.list.d/ros-latest.list && \
	apt-get update && \
	apt-get install -y ros-kinetic-desktop-full ros-kinetic-rviz-visual-tools ros-kinetic-octomap* ros-kinetic-ompl
    cp /opt/ros/kinetic/lib/aarch64-linux-gnu/pkgconfig/opencv-3.3.1-dev.pc /opt/ros/kinetic/lib/aarch64-linux-gnu/pkgconfig/opencv.pc 
    cd $base_dir/build
    echo "done" > ros_install_done.txt
fi

#--- point cloud library
cd $base_dir/src
if [[ ! -d "pcl" ]]; then
    cd $base_dir/src && git clone https://github.com/PointCloudLibrary/pcl.git &&\
    cd pcl && git checkout pcl-1.7.2rc2.1
fi


# for some reason this is not necessary in the docker (but otherwise pcl
# is gonna issue an error
cd /usr/lib/aarch64-linux-gnu/
sudo ln -sf tegra/libGL.so libGL.so

cd $mavbench_base_dir/pcl
if [[ ! `git status --porcelain`  ]]; then
    cp $base_dir/build-scripts/lzf_image_io.cpp $base_dir/src/pcl/io/src/ 
fi

cd $base_dir/src/pcl && mkdir -p build && cd build && cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-std=c++11" ..
cd $base_dir/src/pcl/build && make -j 4
cd $base_dir/src/pcl/build && make -j 4 install

# TODO: this is gonna cause linker for libs that use pcl to run everytime
#       somehow, we need to figure out how to avoid doing it everytime
cd $mavbench_base_dir/build-deps && chmod +x relocate_pcl.sh && ./relocate_pcl.sh

# airsim
#cd $mavbench_base_dir
#if [[ ! -d "AirSim" ]];then
#    cd $mavbench_base_dir/ && git clone https://github.com/hngenc/AirSim.git
#    cd $mavbench_base_dir/"AirSim" &&\
#    git fetch origin &&\
#    git branch future_darwing_dev origin/future_darwing_dev  &&\
#    git checkout future_darwing_dev
#fi    
#
cd $AirSim_base_dir &&\
    ./setup.sh && \
    ./build.sh
