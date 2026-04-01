# Building Documentation
## Building locally:

#### Build Instructions
- [Build and install RAFT](source/build.md) - General build instructions for all platforms
- [Building on aarch64 with CUDA 13.2](source/build_aarch64_cuda132.md) - Specific instructions for ARM-based systems with CUDA 13.2+

#### Generate the docs
```shell script
bash build.sh docs
```

#### Once the process finishes, documentation can be found in build/html
```shell script
xdg-open build/html/index.html
```
