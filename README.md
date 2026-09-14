# aiolos

A fork of the [aiolos](https://github.com/Schulik/aiolos) project. Created mostly to try out certain improvements such as introducing CMake and vcpkg, along with fixing some bugs. The plan is to submit all that back via pull requests.

The `README.txt` file is the original README.

<!-- MarkdownTOC -->

- [Dependencies](#dependencies)
- [Building](#building)
- [Running](#running)
    - [Parallelism and performance](#parallelism-and-performance)
    - [Tests](#tests)
    - [Cleaning](#cleaning)
- [Convenience wrapper script](#convenience-wrapper-script)

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
```

## Running

``` sh
$ ./install/macos-arm64/bin/aiolos \
    -dir ./test_files/ \
    -par planet_spherical.par \
    -spc mix3.spc
```

At the moment, due to an unfortunate(?) design, the executable will only work if you launch it from the repository root.

### Parallelism and performance

The executable is built with OpenMP, but by default it runs only with one thread. To raise it, provide the `-n` argument, like this:

``` sh
$ ./install/macos-arm64/bin/aiolos \
    -dir ./test_files/ \
    -par planet_spherical.par \
    -spc mix3.spc \
    -n 8
```

or, if using the [wrapper script](#convenience-wrapper-script), after the `--` separator:

``` sh
$ ./run-aiolos.sh -p parameters.par -s species.spc -- -n 8
```

To verify that it worked, check the simulation output for a string like:

```
Running with OMP, omp_thread_num = N
```

Worth to mention that setting the usual `OMP_NUM_THREADS` environment variable has no effect, because `aiolos` couldn't give two shits about it - the number is hardcoded and can be changed only with `-n`.

But before you even start considering parallelism: there is only one parallel loop in the entire project, and it is in the general thermo/photochemistry solver, which only runs if your parameter file sets `PHOTOCHEM_LEVEL 2`. Everything else (*hydrodynamics, radiation transport, drag, opacities and the `PHOTOCHEM_LEVEL 1` solver*) is single-threaded. As `PHOTOCHEM_LEVEL` defaults to `0` and none of the parameter files shipped in this repository ask for level `2`, in practice the providing `-n` argument will most likely not make your simulation any faster at all.

What does help, at the cost of having to re-configure and re-build the project, is fixing the species count at compile time (*should bring a 10-20% gain, but the resulting build will be valid only for simulations with exactly that many species*) and enabling link-time optimization:

``` sh
$ cmake --preset macos-arm64 -DNUM_SPECIES=1 -DAIOLOS_LTO=YES
$ cmake --build --preset macos-arm64
```

The `-march=native` optimization is already enabled by default (*the `AIOLOS_NATIVE_ARCH` option*).

Other than that, the number of outgoing radiation bands (`NUM_BANDS_OUT`) is what dominates the cost of the radiation solver (*according to `init_and_bounds.cpp`*), so lowering it is another performance lever that you have.

### Tests

Having built the project, to run the tests:

``` sh
$ ctest --preset macos-arm64
```

The test presets pass `--output-on-failure`, which is what makes a failing Python checker show its numbers instead of just its name. Without using a preset, you would have specify this explicitly:

``` sh
$ ctest --test-dir ./build/macos-arm64 --output-on-failure
```

### Cleaning

To delete output files and tests artifacts:

``` sh
$ cmake --build --preset macos-arm64 --target clean-outputs
```

## Convenience wrapper script

For convenience, there is `./run-aiolos.sh` script for running a simulation with your own input files, keeping those separate from the ones shipped in `./test_files/` (*also `./test2/` and others?*) from the original repository. It also groups the results from every run in a sub-folder of its own, unlike the original "design" where it just craps all over the same path every time.

The script expects `aiolos` executable to be already [built and installed](#building) into `./install/CMAKE-PRESET-NAME/bin/aiolos`.

To run the script, place your parameter (*`parameters.par`*) and species (*`species.spc`*) files into the `./wrk/` folder. If it does not exist, create the folder first. And then:

``` sh
$ ./run-aiolos.sh -p parameters.par -s species.spc
```

Both arguments are just names of the files without a path - the script will look for them inside `./wrk/` folder (*because that is how `aiolos` itself works*). The results (*along with the copies of the input files for this task*) will end up in a new sub-folder with a name based on the timestamp:

``` sh
./wrk/
├── parameters.par
├── species.spc
├── ...
└── results-2026-09-13-225754/
    ├── diagnostic_parameters_t0.dat
    ├── ...
    ├── monitor_parameters.dat
    ├── parameters.par
    ├── species.spc
    └── run.log
```

The `run.log` contains what simulation printed during the run.

There is also `-c` argument for specifying CMake preset, which defaults to `macos-arm64`, so if this is your target platform, then you don't need to specify it.

To view the script help:

``` sh
$ ./run-aiolos.sh -h
```
