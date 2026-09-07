#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
runtime_dir="${project_dir}/.eva-runtime/llama.cpp-omni"
runtime_revision="164819778518de000de2d2e323147d8d1ac4bc5c"

command -v cmake >/dev/null || {
  echo "CMake is required. Install it with: brew install cmake" >&2
  exit 1
}

if [[ ! -d "${runtime_dir}/.git" ]]; then
  mkdir -p "${runtime_dir:h}"
  git clone https://github.com/tc-mb/llama.cpp-omni.git "${runtime_dir}"
fi

git -C "${runtime_dir}" fetch --depth 1 origin "${runtime_revision}"
git -C "${runtime_dir}" checkout --detach "${runtime_revision}"

for patch_name in loopback-server decode-completion; do
  patch_file="${project_dir}/Research/NativeSpeech/${patch_name}.patch"
  if git -C "${runtime_dir}" apply --reverse --check "${patch_file}" 2>/dev/null; then
    echo "${patch_name} patch already applied."
  else
    git -C "${runtime_dir}" apply --check "${patch_file}"
    git -C "${runtime_dir}" apply "${patch_file}"
  fi
done

# The lab uses loopback HTTP. The upstream server creates an invalid SSLServer
# when OpenSSL is enabled without certificates, then exits without listening.
cmake -S "${runtime_dir}" -B "${runtime_dir}/build" -DCMAKE_BUILD_TYPE=Release -DLLAMA_OPENSSL=OFF
cmake --build "${runtime_dir}/build" --target llama-omni-server -j "$(sysctl -n hw.logicalcpu)"

echo "Native speech runtime ready: ${runtime_dir}/build/bin/llama-omni-server"
