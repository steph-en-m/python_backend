#!/bin/bash
# Copyright 2021-2023, NVIDIA CORPORATION & AFFILIATES. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

USAGE="
usage: setup.sh [options]

Sets up python execution environment for AWS Neuron SDK for execution on Inferentia chips.
-h|--help                  Shows usage
-b|--python-backend-path   Python backend path, default is: /home/ubuntu/python_backend
-v|--python-version        Python version, default is 3.7
-i|--inferentia-path       Inferentia path, default is: /home/ubuntu
-p|--use-pytorch           Install pytorch-neuron if specified
-t|--use-tensorflow        Install tensorflow-neuron is specified
--tensorflow-version       Version of Tensorflow used. Default is 1. Ignored if installing pytorch-neuron
"

# Get all options:
OPTS=$(getopt -o hb:v:i:tp --long help,python-backend-path:,python-version:,inferentia-path:,use-tensorflow,use-pytorch,tensorflow-version: -- "$@")


export INFRENTIA_PATH=${TRITON_PATH:="/home/ubuntu"}
export PYTHON_BACKEND_PATH="/home/ubuntu/python_backend"
export PYTHON_VERSION=3.7
export USE_PYTORCH=0
export USE_TENSORFLOW=0
export TENSORFLOW_VERSION=1
for OPTS; do
    case "$OPTS" in
        -h|--help)
        printf "%s\\n" "$USAGE"
        return 0
        ;;
        -b|--python-backend-path)
        PYTHON_BACKEND_PATH=$2
        echo "Python backend path set to ${PYTHON_BACKEND_PATH}"
        shift 2
        ;;
        -v|--python-version)
        PYTHON_VERSION=$2
        shift 2
        echo "Python version set to ${PYTHON_VERSION}"
        ;;
        -i|--inferentia-path)
        INFRENTIA_PATH=$2
        echo "Inferentia path set to ${INFRENTIA_PATH}"
        shift 2
        ;;
        -t|--use-tensorflow)
        USE_TENSORFLOW=1
        echo "Installing tensorflow-neuron"
        shift 1
        ;;
        -p|--use-pytorch)
        USE_PYTORCH=1
        echo "Installing pytorch-neuron"
        shift 1
        ;;
        --use-tensorflow-version)
        TENSORFLOW_VERSION=$2
        echo "Tensorflow version: $TENSORFLOW_VERSION"
        shift 2
        ;;
    esac
done

if [ $USE_TENSORFLOW -ne 1 ] && [ $USE_PYTORCH -ne 1 ]; then
    echo "Need to specify either -p (use pytorch) or -t (use tensorflow)."
    printf "%s\\n" "$USAGE"
    return 1
fi

if [ $USE_TENSORFLOW -eq 1 ] && [ $USE_PYTORCH -eq 1 ]; then
    echo "Can specify only one of -p (use pytorch) or -t (use tensorflow)."
    printf "%s\\n" "$USAGE"
    return 1
fi

if [ $USE_TENSORFLOW -eq 1 ]; then
    if [ $TENSORFLOW_VERSION -ne 1 ] && [ $TENSORFLOW_VERSION -ne 2 ]; then
        echo "Need to specify --tensorflow-version to be 1 or 2. TENSORFLOW_VERSION currently is: $TENSORFLOW_VERSION"
        printf "%s\\n" "$USAGE"
        return 1
    fi
fi

# Install python_backend_stub installing dependencies
apt-get update && \
    apt-get install -y --no-install-recommends \
              zlib1g-dev \
              wget \
              libarchive-dev   \
              rapidjson-dev

# Using CMAKE installation instruction from:: https://apt.kitware.com/
apt install -y gpg wget && \
    wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | \
        gpg --dearmor - |  \
        tee /usr/share/keyrings/kitware-archive-keyring.gpg >/dev/null && \
    . /etc/os-release && \
    echo "deb [signed-by=/usr/share/keyrings/kitware-archive-keyring.gpg] https://apt.kitware.com/ubuntu/ $UBUNTU_CODENAME main" | \
    tee /etc/apt/sources.list.d/kitware.list >/dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends cmake cmake-data
cmake --version

# First compile correct python stub
cd ${PYTHON_BACKEND_PATH}
rm -rf build && mkdir build && cd build
cmake -DTRITON_ENABLE_GPU=ON -DCMAKE_INSTALL_PREFIX:PATH=`pwd`/install ..
make triton-python-backend-stub -j16

# Set Pip repository  to point to the Neuron repository
# since we need to use pip to update: 
#  https://aws.amazon.com/blogs/developer/neuron-conda-packages-eol/
pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com

python -m pip install -U pip
# Set pip repository pointing to the Neuron repository 
python -m pip config set global.extra-index-url https://pip.repos.neuron.amazonaws.com
if [ $USE_TENSORFLOW -eq 1 ]; then
    # Update Neuron TensorFlow
    if [ $TENSORFLOW_VERSION -eq 1 ]; then
        # Install TensorFlow Neuron
        python -m pip install tensorflow-neuron[cc]==1.15.5.* "protobuf"
    else
        # Install TensorFlow Neuron
        python -m pip install tensorflow-neuron[cc] "protobuf"
    fi
fi

if [ $USE_PYTORCH -eq 1 ]
then
    # Install PyTorch Neuron
    python -m pip install torch-neuron neuron-cc[tensorflow] "protobuf" torchvision
fi

# Upgrade the python backend stub, rules and sockets
cp ${INFRENTIA_PATH}/python_backend/build/triton_python_backend_stub \
        /opt/tritonserver/backends/python/triton_python_backend_stub
cp /mylib/udev/rules.d/* /lib/udev/rules.d/
export LD_LIBRARY_PATH=${CONDA_PATH}/envs/test_conda_env/lib:$LD_LIBRARY_PATH

cd ${INFRENTIA_PATH}
