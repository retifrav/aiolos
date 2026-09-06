# aiolos

A fork of the [aiolos](https://github.com/Schulik/aiolos) project. Created mostly to try out certain improvements such as introducing CMake and vcpkg, along with fixing some bugs. The plan is to submit all that back via pull requests.

The `README.txt` file is the original README.

<!-- MarkdownTOC -->

- [Dependencies](#dependencies)
- [Building and running](#building-and-running)
    - [Tests](#tests)
    - [Cleaning](#cleaning)

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

## Building and running

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

### Tests

To run the tests:

``` sh
$ ctest --test-dir build/macos-arm64
```

or:

``` sh
$ cmake --build --preset macos-arm64 --target run-tests
```

### Cleaning

To delete output file or/and tests artifacts:

``` sh
$ cmake --build --preset macos-arm64 --target clean-outputs
```
