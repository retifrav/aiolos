# aiolos

A fork of the [aiolos](https://github.com/Schulik/aiolos) project. Created mostly to try out certain improvements such as introducing CMake and vcpkg, along with fixing some bugs. The plan is to submit all that back via pull requests.

The `README.txt` file is the original README.

<!-- MarkdownTOC -->

- [Dependencies](#dependencies)
- [Building](#building)

<!-- /MarkdownTOC -->

## Dependencies

Dependencies are resolved via vcpkg, but [OpenMP](https://openmp.org/) in particular is expected to be installed with a system package manager.

On Mac OS:

``` sh
$ brew install libomp
```

On Linux (*assuming that you will be using gcc*):

``` sh
$ sudo apt install build-essential
```

## Building

Use the appropriate CMake preset depending on your platform:

``` sh
$ cd /path/to/aiolos/

$ cmake --preset macos-arm64
$ cmake --build --preset macos-arm64

$ ./install/macos-arm64/bin/aiolos \
    -dir ./test_files/ \
    -par planet_spherical.par \
    -spc mix3.spc
```

At the moment, due to an unfortunate(?) design, the executable will only work if you launch it from the repository root.
